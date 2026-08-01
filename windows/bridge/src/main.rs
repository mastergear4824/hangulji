#[cfg(windows)]
mod hook;

#[cfg(windows)]
fn main() {
    println!("한글지 브리지 — 2벌식 키를 MS-IME 로마자로 변환해 주입합니다.");
    println!("사전 조건: 일본어 IME(MS-IME) 활성 + ひらがな 모드 + 로마자 입력 설정");
    println!("토글: Ctrl+Space / 종료: 이 창에서 Ctrl+C");
    println!("한계: 관리자 권한 창·보안 데스크톱에는 주입되지 않습니다 (README.md 참고)");
    if let Err(e) = hook::run() {
        eprintln!("키보드 훅 설치 실패: {e}");
        std::process::exit(1);
    }
}

#[cfg(not(windows))]
fn main() {
    eprintln!("hangulji-bridge는 Windows 전용 실행 파일입니다.");
    eprintln!("변환 로직 테스트는 어느 OS에서나: cargo test --manifest-path windows/bridge/Cargo.toml");
    std::process::exit(2);
}
