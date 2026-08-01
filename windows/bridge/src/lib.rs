//! 한글지 Windows 브리지 — 순수(플랫폼 무관) 변환 로직.
//! Windows 셸(훅·주입)은 bin 크레이트(main.rs + hook.rs)에만 있다.

pub mod table_generated;
pub mod translator;
