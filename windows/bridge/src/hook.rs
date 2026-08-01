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

fn char_to_vk(c: char) -> VIRTUAL_KEY {
    match c {
        'a'..='z' => VIRTUAL_KEY(c.to_ascii_uppercase() as u16), // VK_A..VK_Z == 'A'..'Z'
        '-' => VK_OEM_MINUS,
        _ => unreachable!("생성 테이블 출력은 [a-z-] 뿐 (gen-bridge-table이 보장)"),
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
fn send_romaji(romaji: &str) {
    if romaji.is_empty() {
        return;
    }
    let mut inputs: Vec<INPUT> = Vec::with_capacity(romaji.len() * 2 + 2);
    let shift_held = key_down(VK_SHIFT);
    if shift_held {
        inputs.push(key_event(VK_SHIFT, true)); // 일시 해제
    }
    for c in romaji.chars() {
        let vk = char_to_vk(c);
        inputs.push(key_event(vk, false));
        inputs.push(key_event(vk, true));
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
