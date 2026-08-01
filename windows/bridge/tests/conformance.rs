//! spec/fixtures conformance 러너 (SPEC.md §6 — 포트의 러너 의무).
//! 검증 고리: 2벌식 키 → [translator] → 로마자 → [오라클: ROMAJI_TO_KANA automaton
//! = MS-IME 로마자 처리의 결정적 부분집합] → 가나 == 픽스처 기대값.
//! Windows 없이 CI에서 변환 로직의 루프를 닫는다. MS-IME 실물이 같은 철자를
//! 수용하는지만 실기기 검증 보류 항목이다 (windows/bridge/README.md).

use hangulji_bridge::table_generated::{KEY_TO_ROMAJI, ROMAJI_TO_KANA};
use hangulji_bridge::translator::Automaton;
use serde::Deserialize;
use std::path::PathBuf;

#[derive(Deserialize)]
struct KanaCase {
    name: String,
    keys: String,
    kana: String,
    #[serde(rename = "fullyMapped")]
    fully_mapped: bool,
}

#[derive(Deserialize)]
struct CompositionCase {
    #[allow(dead_code)]
    name: String,
    keys: String,
    #[allow(dead_code)]
    syllables: Vec<String>,
}

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/fixtures").join(name)
}

/// 키 시퀀스 → (translator) 로마자 → (오라클) 가나
fn keys_to_kana(keys: &str) -> String {
    let mut translator = Automaton::new(KEY_TO_ROMAJI);
    let mut oracle = Automaton::new(ROMAJI_TO_KANA);
    let mut kana = String::new();
    for ch in keys.chars() {
        for r in translator.push(ch).chars() {
            kana.push_str(&oracle.push(r));
        }
    }
    for r in translator.flush().chars() {
        kana.push_str(&oracle.push(r));
    }
    kana.push_str(&oracle.flush());
    kana
}

#[test]
fn kana_fixtures_roundtrip_through_msime_romaji() {
    let data = std::fs::read_to_string(fixture("kana.json")).expect("kana.json 읽기");
    let cases: Vec<KanaCase> = serde_json::from_str(&data).expect("kana.json 파싱");
    let mut checked = 0;
    for case in &cases {
        if !case.fully_mapped {
            // 브리지는 호스트 IME에 로마자를 흘리므로 한글을 출력할 수 없다 —
            // 매핑 불가 케이스는 무패닉·비어있지 않은 결정적 열화만 확인
            // (1단계 MozcTableTests 선례와 동일. windows/bridge/README.md 한계 절 문서화)
            assert!(!keys_to_kana(&case.keys).is_empty(), "{}", case.name);
            continue;
        }
        assert_eq!(keys_to_kana(&case.keys), case.kana, "케이스 {}", case.name);
        checked += 1;
    }
    assert!(checked >= 38, "fullyMapped 케이스가 SPEC §6.1 최소치(38) 미만: {checked}");
}

#[test]
fn composition_fixtures_smoke() {
    // 브리지에는 자모 음절 조합기(JamoComposer)가 없어 §6.2의 한글 음절 목록 검증은
    // 구조적으로 불가 — 전 케이스 무패닉 처리 + §2.3 받침 재해석 의미론은 아래
    // batchim_reanalysis_traces가 가나 레벨에서 고정한다 (1단계 선례와 동일한 범위 한정)
    let data = std::fs::read_to_string(fixture("composition.json")).expect("composition.json 읽기");
    let cases: Vec<CompositionCase> = serde_json::from_str(&data).expect("composition.json 파싱");
    assert!(cases.len() >= 8);
    for case in &cases {
        let _ = keys_to_kana(&case.keys); // 무패닉·결정적 처리 확인
    }
}

#[test]
fn batchim_reanalysis_traces() {
    assert_eq!(keys_to_kana("rksl"), "がに");      // 가+니 — 받침 재해석 (composition: reanalysis-kani)
    assert_eq!(keys_to_kana("rksdl"), "がんい");   // 간+이 — 명시적 ㅇ (explicit-ng-kan-i)
    assert_eq!(keys_to_kana("rks"), "がん");       // 어말 받침 — flush 확정
    assert_eq!(keys_to_kana("tktvh"), "さっぽ");   // 삿+포 — 촉음 연쇄 (final-then-consonant)
    assert_eq!(keys_to_kana("zkEk"), "かた");      // ㄸ는 받침 불가 → 새 음절 (dd-cannot-be-final)
    assert_eq!(keys_to_kana("dh"), "お");          // 복합모음(ㅘ) 대기 중 flush → お 확정
}
