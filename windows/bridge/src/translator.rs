//! 순수(플랫폼 무관) 테이블 automaton — 1단계 Google IME 로마자 테이블과 같은 의미론.
//! (input, output, next_input) 규칙 집합에 대해 키를 pending에 누적하며:
//!   1. pending이 어떤 input의 진접두사이면 → 대기 (경계(flush)에서는 정확 일치 우선 확정)
//!   2. pending이 정확 일치하고 확장 불가면 → output 방출, pending = next_input
//!   3. 둘 다 아니면 → 최장 정확 접두사를 확정해 분리, 그것도 없으면 첫 키를 raw로 방출
//! 같은 코드가 두 규칙 집합에 쓰인다:
//!   - KEY_TO_ROMAJI: 2벌식 키 → 로마자 (브리지 본체 — 받침 대기·재해석이 여기서 해결됨)
//!   - ROMAJI_TO_KANA: 로마자 → 가나 (테스트 오라클 — 접두사 자유 표라 대기는 모라 중간뿐)
//! raw 방출(규칙 3 말단)은 매핑 불가 키(단독 모음 등)의 결정적 열화 경로다 — 1단계에서
//! Google IME에 라틴 문자가 그대로 남는 것과 동급이며 README 한계 절에 문서화한다.

use std::collections::{HashMap, HashSet};

pub struct Automaton {
    rules: HashMap<&'static str, (&'static str, &'static str)>,
    prefixes: HashSet<String>, // 모든 input의 진접두사 집합
    pending: String,
}

impl Automaton {
    pub fn new(table: &'static [(&'static str, &'static str, &'static str)]) -> Self {
        let mut rules = HashMap::new();
        let mut prefixes = HashSet::new();
        for &(input, output, next) in table {
            let dup = rules.insert(input, (output, next));
            assert!(dup.is_none(), "중복 input: {input}");
            let chars: Vec<char> = input.chars().collect();
            for i in 1..chars.len() {
                prefixes.insert(chars[..i].iter().collect());
            }
        }
        Automaton { rules, prefixes, pending: String::new() }
    }

    /// 키 1개 소비 — 지금 확정되는 출력(대기 중이면 빈 문자열)을 돌려준다.
    pub fn push(&mut self, ch: char) -> String {
        self.pending.push(ch);
        self.resolve(false)
    }

    /// 커밋 경계(스페이스·엔터·토글 등): pending 전부를 정확 일치 우선으로 해소.
    pub fn flush(&mut self) -> String {
        self.resolve(true)
    }

    /// 백스페이스: 아직 방출되지 않은 pending의 마지막 키 1개 제거. 비었으면 false.
    pub fn pop_pending(&mut self) -> bool {
        self.pending.pop().is_some()
    }

    pub fn pending_len(&self) -> usize {
        self.pending.chars().count()
    }

    /// pending을 출력 없이 버린다. flush()와 달리 커밋하지 않는다 — 토글 끔처럼
    /// "지금까지 대기 중이던 입력은 포기하고 다음부터 깨끗하게 시작" 하는 상태
    /// 리셋 전용이다.
    pub fn clear_pending(&mut self) {
        self.pending.clear();
    }

    fn resolve(&mut self, at_boundary: bool) -> String {
        let mut out = String::new();
        loop {
            if self.pending.is_empty() {
                return out;
            }
            let has_ext = self.prefixes.contains(&self.pending);
            if let Some(&(output, next)) = self.rules.get(self.pending.as_str()) {
                if !has_ext || at_boundary {
                    out.push_str(output);
                    self.pending = next.to_string();
                    continue;
                }
            }
            if has_ext && !at_boundary {
                return out; // 더 긴 항목 가능성 — 대기
            }
            // 정확 일치 없음 → 최장 정확 접두사 분리, 그것도 없으면 첫 키 raw 방출
            let chars: Vec<char> = self.pending.chars().collect();
            let mut split = 0;
            for len in (1..=chars.len()).rev() {
                let p: String = chars[..len].iter().collect();
                if self.rules.contains_key(p.as_str()) {
                    split = len;
                    break;
                }
            }
            if split == 0 {
                out.push(chars[0]);
                self.pending = chars[1..].iter().collect();
            } else {
                let p: String = chars[..split].iter().collect();
                let &(output, next) = self.rules.get(p.as_str()).unwrap();
                out.push_str(output);
                let rest: String = chars[split..].iter().collect();
                self.pending = format!("{next}{rest}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Automaton;
    use crate::table_generated::KEY_TO_ROMAJI;

    fn run(keys: &str) -> String {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        let mut out = String::new();
        for ch in keys.chars() {
            out.push_str(&a.push(ch));
        }
        out.push_str(&a.flush());
        out
    }

    #[test]
    fn emits_msime_romaji() {
        assert_eq!(run("xhdnzydnsldlzlaktm"), "toukyouniikimasu"); // 토우쿄우니이키마스
        assert_eq!(run("rksdl"), "ganni");             // ん은 항상 nn — n 모호성 원천 차단
        assert_eq!(run("tktvhfh"), "saxtuporo");       // っ은 항상 xtu — 자음 중복 표기 불사용
        assert_eq!(run("ghtRkdlehdn"), "hoxtukaidou"); // 홋(ㅅ받침 연쇄) + 까(Shift+R 별칭)
        assert_eq!(run("fk-aps"), "ra-menn");          // 장음 '-' 는 그대로 통과
    }

    #[test]
    fn waits_while_prefix_open() {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        assert_eq!(a.push('g'), "");   // ㅎ — 모음 대기
        assert_eq!(a.push('h'), "");   // ㅗ — ghk(화=ふぁ) 가능성 대기
        assert_eq!(a.push('k'), "fa"); // 화 확정
        assert_eq!(a.pending_len(), 0);
    }

    #[test]
    fn pop_pending_cancels_unemitted_key() {
        let mut a = Automaton::new(KEY_TO_ROMAJI);
        assert_eq!(a.push('z'), "");
        assert!(a.pop_pending());
        assert_eq!(a.push('g'), "");
        assert_eq!(a.push('k'), "ha"); // z 취소 후 gk = 하
        assert!(!a.pop_pending()); // pending 비어 있음
    }

    #[test]
    fn unmappable_degrades_deterministically() {
        // 별(quf): 몸통 ㅂ+ㅕ 미배정 → q는 받침 っ로, u·f는 raw로 샌다.
        // 1단계의 "っuf"와 동급의 결정적 열화 — README 한계 절에 문서화되는 동작의 고정.
        assert_eq!(run("quf"), "xtuuf");
    }
}
