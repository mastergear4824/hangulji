//! Windows 셸: WH_KEYBOARD_LL 훅 + SendInput 로마자 주입.
//! 이 모듈의 책임 범위는 CI 컴파일 검증까지 — 실기기 실행 검증은 보류(설계 §5.4·§8).
//!
//! 원칙 (리서치 확정 사항):
//! 1. 훅 프로시저는 트리비얼해야 한다(LowLevelHooksTimeout 초과 시 OS가 훅 제거):
//!    분류 + 채널 송신 + 삼킴 판정만. 변환·SendInput은 워커 스레드.
//! 2. LLKHF_INJECTED 이벤트는 무조건 즉시 통과 — 자기 주입 재귀 방지 (첫 검사).
//! 3. KEYEVENTF_UNICODE 금지: VK 키만 주입해야 MS-IME 로마자 automaton이 소비한다.
//! 4. IME 상태 추적 대신 자체 토글(Ctrl+Space) — 보안 데스크톱·관리자 창 도달 불가는
//!    구조적 한계로 README에 문서화.

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::OnceLock;

use hangulji_bridge::table_generated::KEY_TO_ROMAJI;
use hangulji_bridge::translator::Automaton;

use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
    VIRTUAL_KEY, VK_BACK, VK_CONTROL, VK_MENU, VK_OEM_MINUS, VK_SHIFT, VK_SPACE,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage,
    KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_SYSKEYDOWN,
};

enum Msg {
    /// 한글지 키 — translator로
    Key(char),
    /// 비매핑 키가 pending 중 도착 — flush 후 원 키를 재주입해 순서 보장
    /// (원 키를 통과시키면 flush 로마자보다 먼저 도착해 IME 변환 순서가 역전된다)
    Boundary(u16),
    /// 백스페이스 — 화면 미표시 pending 1키 취소
    BackspacePending,
    /// 토글 끔(Ctrl+Space) — pending을 출력 없이 버려 재활성화 시 깨끗한 상태로 시작
    ResetPending,
}

static ENABLED: AtomicBool = AtomicBool::new(true);
// 훅 스레드의 동기 삼킴 판정용으로 워커가 갱신하는 pending 길이 사본.
// 채널에 미처리 키가 있는 짧은 순간 구식 값일 수 있다(빠른 타이핑 시) — README 한계 문서화.
static PENDING_LEN: AtomicUsize = AtomicUsize::new(0);
static TX: OnceLock<Sender<Msg>> = OnceLock::new();

pub fn run() -> windows::core::Result<()> {
    let (tx, rx) = channel::<Msg>();
    TX.set(tx).expect("run()은 1회만 호출");

    // 워커: translator 상태 소유. 훅 프로시저는 여기에 채널로만 접근한다.
    std::thread::spawn(move || {
        let mut translator = Automaton::new(KEY_TO_ROMAJI);
        for msg in rx {
            match msg {
                Msg::Key(ch) => {
                    let romaji = translator.push(ch);
                    PENDING_LEN.store(translator.pending_len(), Ordering::SeqCst);
                    send_romaji(&romaji);
                }
                Msg::Boundary(vk) => {
                    let romaji = translator.flush();
                    PENDING_LEN.store(0, Ordering::SeqCst);
                    send_romaji(&romaji);
                    send_vk(VIRTUAL_KEY(vk)); // 삼킨 원 키 재주입 (LLKHF_INJECTED로 통과됨)
                }
                Msg::BackspacePending => {
                    translator.pop_pending();
                    PENDING_LEN.store(translator.pending_len(), Ordering::SeqCst);
                }
                Msg::ResetPending => {
                    translator.clear_pending();
                    PENDING_LEN.store(0, Ordering::SeqCst);
                }
            }
        }
    });

    unsafe {
        let _hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook_proc), None, 0)?;
        println!("한글지 브리지 동작 중 — Ctrl+Space 토글, 이 창에서 Ctrl+C 종료");
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            let _ = DispatchMessageW(&msg);
        }
    }
    Ok(())
}

fn key_down(vk: VIRTUAL_KEY) -> bool {
    unsafe { (GetAsyncKeyState(vk.0 as i32) as u16) & 0x8000 != 0 }
}

/// vkCode(+Shift) → 한글지 키 문자. SPEC §1.1 구현: 명시 배정된 대문자(Q W E R T O P)만
/// 대문자 유지, 그 외 Shift+알파벳은 소문자로 폴백. Shift+'-'(_)는 비매핑.
/// O·P 대문자(ㅒ·ㅖ)는 배정은 있으나 TSV에 몸통이 없어 raw로 새는 열화 경로다(README 문서화).
fn map_char(vk: u32, shift: bool) -> Option<char> {
    if (0x41..=0x5A).contains(&vk) {
        let upper = (vk as u8) as char; // VK_A..VK_Z == 'A'..'Z'
        if shift && matches!(upper, 'Q' | 'W' | 'E' | 'R' | 'T' | 'O' | 'P') {
            Some(upper)
        } else {
            Some(upper.to_ascii_lowercase())
        }
    } else if vk == VK_OEM_MINUS.0 as u32 && !shift {
        Some('-')
    } else {
        None
    }
}

unsafe extern "system" fn hook_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code < 0 {
        return CallNextHookEx(None, code, wparam, lparam);
    }
    let kb = &*(lparam.0 as *const KBDLLHOOKSTRUCT);

    // 1. 자기 주입 재귀 방지 — 최우선
    if kb.flags.contains(LLKHF_INJECTED) {
        return CallNextHookEx(None, code, wparam, lparam);
    }

    let is_down =
        wparam.0 as u32 == WM_KEYDOWN || wparam.0 as u32 == WM_SYSKEYDOWN;
    let ctrl = key_down(VK_CONTROL);

    // 2. 토글: Ctrl+Space (설계 §5.4 — IME 상태 추적 대신 자체 토글)
    if is_down && ctrl && kb.vkCode == VK_SPACE.0 as u32 {
        let was_enabled = ENABLED.fetch_xor(true, Ordering::SeqCst);
        if was_enabled {
            // 끄는 순간: pending을 출력 없이 버려 재활성화 시 깨끗한 상태로 시작
            // (MINOR 수정 — 안 하면 꺼져 있던 동안의 무관한 타이핑이 재활성화 후
            // 예전 pending과 합쳐져 엉뚱하게 변환될 수 있다)
            let _ = TX.get().unwrap().send(Msg::ResetPending);
        }
        println!("한글지 브리지: {}", if was_enabled { "꺼짐" } else { "켜짐" });
        return LRESULT(1);
    }

    // 3. 꺼짐 상태·단축키(Ctrl/Alt 동반)는 건드리지 않는다 (Ctrl+C 등 보존)
    if !ENABLED.load(Ordering::SeqCst) || ctrl || key_down(VK_MENU) {
        return CallNextHookEx(None, code, wparam, lparam);
    }

    // 4. 한글지 키 → 삼키고 워커로 (down/up 모두 삼켜 짝 없는 keyup 방지)
    if let Some(ch) = map_char(kb.vkCode, key_down(VK_SHIFT)) {
        if is_down {
            let _ = TX.get().unwrap().send(Msg::Key(ch));
        }
        return LRESULT(1);
    }

    // 5. 비매핑 키가 pending 중 도착 (keydown만 개입 — keyup은 통과)
    if is_down && PENDING_LEN.load(Ordering::SeqCst) > 0 {
        if kb.vkCode == VK_BACK.0 as u32 {
            // pending 키는 화면에 없으므로 백스페이스를 앱까지 보내지 않는다
            let _ = TX.get().unwrap().send(Msg::BackspacePending);
            return LRESULT(1);
        }
        // 스페이스·엔터·숫자 등: flush 후 원 키 재주입 (순서 보장)
        let _ = TX.get().unwrap().send(Msg::Boundary(kb.vkCode as u16));
        return LRESULT(1);
    }

    CallNextHookEx(None, code, wparam, lparam)
}

/// 로마자 문자 1개 → (VK, 이 문자 전용 Shift 랩 필요 여부).
/// - `'a'..='z'`·`'-'`: 그대로, Shift 랩 불필요.
/// - `'A'..='Z'`: Automaton 규칙 3(raw 방출)의 열화 경로로 새어나올 수 있다 — 예를 들어
///   Shift+O·Shift+P(ㅒ·ㅖ 배정은 있으나 TSV에 몸통이 없음)가 그대로 대문자로 pending에서
///   raw 방출된다(README 한계 절 문서화). 대문자를 앱에 그대로 전달하려면 VK 자체를
///   Shift 없이 누른 뒤 이 문자만을 위한 Shift-down/up으로 감싸 주입해야 한다(호출부
///   `send_romaji`가 처리) — 그렇지 않으면 소문자 VK가 그대로 소문자로 들어간다.
/// - 그 외: 생성 테이블 불변식([a-zA-Z-] 뿐)이 실제로는 지켜지지 않는 예기치 못한
///   입력 — `None`을 돌려주고 호출부가 로그 후 건너뛴다. 이전에는 `unreachable!()`로
///   패닉했고, 패닉은 워커 스레드를 죽여 채널 송신측(훅)이 이후 모든 키를 삼킨 채
///   무한 대기하게 만들었다(MAJOR — 워커는 어떤 문자에도 패닉해서는 안 된다).
fn char_to_vk(c: char) -> Option<(VIRTUAL_KEY, bool)> {
    match c {
        'a'..='z' => Some((VIRTUAL_KEY(c.to_ascii_uppercase() as u16), false)), // VK_A..VK_Z == 'A'..'Z'
        'A'..='Z' => Some((VIRTUAL_KEY(c as u16), true)), // raw-echo 열화: Shift 랩으로 대문자 유지
        '-' => Some((VK_OEM_MINUS, false)),
        _ => None,
    }
}

fn key_event(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: if up { KEYEVENTF_KEYUP } else { Default::default() },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

/// 로마자 문자열을 VK 키스트로크로 주입. KEYEVENTF_UNICODE 금지(Global Constraints).
/// 물리 Shift가 눌린 채(예: ㄲ=Shift+R 직후 tR 연쇄) 소문자 로마자를 주입하면 대문자가
/// 되어 IME 조합이 깨지므로, 주입 전 Shift-up / 주입 후 Shift-down으로 물리 상태를
/// 감쌌다가 복원한다 — 실기기 검증 보류 항목(README).
/// 대문자 raw-echo(Automaton 규칙 3 열화 경로, 예: Shift+O)는 문자 단위로 자체
/// Shift-down/up을 감싸 대문자 그대로 주입한다 — `char_to_vk`가 이를 표시해 준다.
/// 생성 테이블 불변식 밖의 문자(`char_to_vk`가 `None`)는 로그 후 건너뛴다 — 패닉 금지.
fn send_romaji(romaji: &str) {
    if romaji.is_empty() {
        return;
    }
    let mut inputs: Vec<INPUT> = Vec::with_capacity(romaji.len() * 4 + 2);
    let shift_held = key_down(VK_SHIFT);
    if shift_held {
        inputs.push(key_event(VK_SHIFT, true)); // 일시 해제
    }
    for c in romaji.chars() {
        match char_to_vk(c) {
            Some((vk, needs_shift)) => {
                if needs_shift {
                    inputs.push(key_event(VK_SHIFT, false)); // 이 문자 전용 Shift down
                }
                inputs.push(key_event(vk, false));
                inputs.push(key_event(vk, true));
                if needs_shift {
                    inputs.push(key_event(VK_SHIFT, true)); // 이 문자 전용 Shift up
                }
            }
            None => {
                // 생성 테이블 불변식 밖의 문자 — 패닉 대신 로그하고 건너뜀(워커 생존 우선)
                eprintln!("한글지 브리지: char_to_vk 매핑 없음, 건너뜀: {c:?}");
            }
        }
    }
    if shift_held {
        inputs.push(key_event(VK_SHIFT, false)); // 물리 상태 복원
    }
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

fn send_vk(vk: VIRTUAL_KEY) {
    let inputs = [key_event(vk, false), key_event(vk, true)];
    unsafe {
        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

// 이 모듈 전체가 `#[cfg(windows)] mod hook;`(main.rs)로만 컴파일되므로 아래 테스트는
// Windows에서만 실행된다 — `cargo test --manifest-path windows/bridge/Cargo.toml`을
// macOS/Linux에서 돌리면 hook.rs 자체가 빌드 그래프에서 완전히 빠지므로 아래 테스트는
// 세지 않는다(기존 7건 그대로 유지). 실제 실행은 windows-bridge CI(windows-2022,
// `cargo test --release`)에서 이뤄진다. 로컬에서는 타입만
// `cargo check --manifest-path windows/bridge/Cargo.toml --target x86_64-pc-windows-msvc --tests`
// 로 확인했다.
#[cfg(test)]
mod tests {
    use super::*;

    // MAJOR 수정 회귀 테스트: char_to_vk가 이전엔 [a-z-] 밖의 문자에서 unreachable!()로
    // 패닉했다(워커 스레드 사망 → 훅이 키를 계속 삼킴). 지금은 무엇을 넣어도 패닉하지
    // 않고 Option을 돌려준다.

    #[test]
    fn char_to_vk_lowercase_no_shift_wrap() {
        let (vk, needs_shift) = char_to_vk('a').expect("a는 매핑됨");
        assert_eq!(vk.0, b'A' as u16); // VK_A..VK_Z == 'A'..'Z'
        assert!(!needs_shift);
    }

    #[test]
    fn char_to_vk_uppercase_raw_echo_needs_shift_wrap() {
        // Automaton 규칙 3(raw 방출) 경로로 Shift+O 등 대문자가 그대로 샐 수 있다
        // (O·P: ㅒ·ㅖ 배정은 있으나 TSV에 몸통이 없어 raw로 새는 열화 경로 — README 문서화).
        for c in ['Q', 'W', 'E', 'R', 'T', 'O', 'P'] {
            let (vk, needs_shift) = char_to_vk(c).unwrap_or_else(|| panic!("{c}는 매핑됨"));
            assert_eq!(vk.0, c as u16, "대문자는 자기 자신의 VK를 써야 한다: {c}");
            assert!(needs_shift, "대문자는 Shift 랩이 필요하다: {c}");
        }
    }

    #[test]
    fn char_to_vk_minus_passthrough() {
        let (vk, needs_shift) = char_to_vk('-').expect("-는 매핑됨");
        assert_eq!(vk.0, VK_OEM_MINUS.0);
        assert!(!needs_shift);
    }

    #[test]
    fn char_to_vk_unknown_char_returns_none_never_panics() {
        // 생성 테이블 불변식([a-zA-Z-] 뿐) 밖의 입력이 실수로 들어와도 워커가 죽지
        // 않아야 한다 — 이전의 unreachable!()을 대체하는 핵심 회귀 테스트.
        assert!(char_to_vk('!').is_none());
        assert!(char_to_vk('0').is_none());
        assert!(char_to_vk('가').is_none());
    }
}
