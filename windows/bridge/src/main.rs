#[cfg(windows)]
fn main() {
    // Windows 셸은 Task 3에서 구현된다 (hook 모듈).
    println!("한글지 브리지 — 셸 미구현 (Task 3)");
}

#[cfg(not(windows))]
fn main() {
    eprintln!("hangulji-bridge는 Windows 전용 실행 파일입니다.");
    eprintln!("변환 로직 테스트는 어느 OS에서나: cargo test --manifest-path windows/bridge/Cargo.toml");
    std::process::exit(2);
}
