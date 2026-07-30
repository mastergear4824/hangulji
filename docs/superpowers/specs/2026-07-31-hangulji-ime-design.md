# Hangulji — macOS 한글-일본어 입력기 설계

날짜: 2026-07-31
상태: 승인됨 (구현 계획 대기)

## 1. 개요

**Hangulji(한글지)** 는 macOS용 일본어 입력기(IME)다. 사용자는 2벌식 한글 자판으로 일본어 가나의 **철자**를 발음대로 입력하고(토우쿄우), 입력기가 이를 가나(とうきょう)로 실시간 표시하며, 스페이스로 한자 변환(東京)까지 수행한다. 로마지 입력의 한글 버전.

- 1차 사용자: 개발자 본인 (개인 맥, `~/Library/Input Methods` 설치)
- 코드는 나중에 공개 배포 가능한 구조로 작성 (MIT 호환 의존성만 사용)
- macOS에 선례 없는 최초 시도. 유사 선례: Linux ibus-hanjp, Android '한글 발음 일본어 키보드', 웹 변환기 ltool.net

### 목표 (MVP)

내 맥에서 Hangulji를 입력 소스로 선택하고, 아무 앱에서나
"토우쿄우니 이키마스" → [Space] 변환 → **東京に行きます** 를 입력할 수 있다.

### 비목표 (MVP 이후로 미룸)

- 배포 파이프라인 (Developer ID 서명, 공증, .pkg — Squirrel 방식 채택 예정)
- 전용 가타카나 모드 토글 (1차는 후보창의 가타카나 후보로 해결)
- ヴ, 단독 소문자 가나(ぁぃぅぇぉ/ゃゅょ/ッ), 학습·개인화 사전
- hangeul_ime식 '심리스 모드' 최적화 (1차는 마크드 텍스트 방식만)
- 설정 UI (1차는 코드 내 상수)

## 2. 아키텍처

```
┌─ Hangulji.app (IMKit 셸) ──────────────────────┐
│  IMKServer + HanguljiInputController           │
│  후보창 (자체 NSPanel)                          │
└──────────────┬─────────────────────────────────┘
               │ 순수 함수 호출
┌─ HanguljiCore (SPM 라이브러리, 유닛테스트 대상) ─┐
│  JamoComposer: 키 → 자모 → 음절 조합 상태머신    │
│  KanaMapper:   음절 스트림 → 가나 문자열         │
└──────────────┬─────────────────────────────────┘
               │ ComposingText(.direct)
┌─ AzooKeyKanaKanjiConverter (외부 SPM, MIT) ────┐
│  requestCandidates() → 한자 후보 목록           │
└────────────────────────────────────────────────┘
```

### 2.1 HanguljiCore (SPM 라이브러리)

AppKit 의존성 없는 순수 Swift. IME 프로세스는 브레이크포인트 디버깅이 불가능하므로(디버거로 멈추면 데스크톱 전체 키보드가 얼어붙음) 모든 변환 로직을 여기에 격리하고 유닛테스트로 검증한다. 검증된 모든 오픈소스 IME(vChewing, azooKey, macSKK)가 쓰는 구조.

- **JamoComposer**: 키코드 → 2벌식 자모 → 음절 조합. 받침 재해석 포함(간+이 입력 시 "가" + "니"가 아니라 받침ㄴ 확정 후 "이" — 뒤 음절이 ㅇ 초성으로 시작하므로 자동 판정된다. 한글 정서법이 로마지의 n' 문제를 공짜로 해결하는 지점). 자모 단위 백스페이스를 위해 원본 자모 스트림을 유지한다.
- **KanaMapper**: 완성/조합 중 음절 스트림 → 가나 문자열. §4의 매핑 표를 테이블 데이터로 구현. 별칭 정규화 포함.

### 2.2 Hangulji.app (IMKit 셸)

- `IMKInputController` 서브클래스는 얇은 통과 계층: `handle(_:client:)`에서 키를 받아 HanguljiCore에 위임, 반환된 상태로 마크드 텍스트/커밋/후보창을 갱신.
- 번들 ID: `com.mastergear.inputmethod.Hangulji` (`.inputmethod.` 포함 필수 — 없으면 OS가 입력기로 인식하지 않음)
- Info.plist 핵심 키:
  - `InputMethodConnectionName` = `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection` (정확히 이 패턴이어야 함 — 최신 macOS는 다른 이름을 무시하고, 불일치 시 입력 메뉴에서 회색 처리됨)
  - `InputMethodServerControllerClass` = `$(PRODUCT_MODULE_NAME).HanguljiInputController`
  - `tsInputMethodCharacterRepertoireKey` = `["Jpan"]` (일본어 입력기이므로 일본어 섹션에 표시)
  - `tsInputMethodIconFileKey` = 메뉴바 아이콘
  - 단일 모드이므로 `ComponentInputModeDict` 불필요
- 백그라운드 전용 앱(`LSBackgroundOnly`), AppDelegate에서 `IMKServer(name:bundleIdentifier:)` 생성 (ensan-hcl/macOS_IMKitSample_2021 구조)
- 샌드박스: 1차는 비샌드박스(개인용). 샌드박스 적용 시 `com.apple.security.temporary-exception.mach-register.global-name` 필요.

### 2.3 후보창

`IMKCandidates`는 사용하지 않는다 — 실무에서 못 쓰는 API로 판명(창이 메뉴/Spotlight에 가려짐, 선택키가 프라이빗 API 없이 동작 안 함, macOS 26 렌더링 버그. vChewing·azooKey·Gureum 전부 자체 구현으로 이탈). 심플한 자체 NSPanel: 세로 목록, 숫자키 선택, 커서 위치 아래 표시(`client.attributes(forCharacterIndex:)` 기반).

### 2.4 변환 엔진

**AzooKeyKanaKanjiConverter** (github.com/azooKey/AzooKeyKanaKanjiConverter)

- MIT 라이선스(사전은 Apache-2.0), 순수 Swift, macOS 13+, 실전 검증됨(azooKey-Desktop이 동일 용도로 사용)
- 사용 방식: `KanaKanjiConverter.withDefaultDictionary()` → `ComposingText`에 가나를 `.direct` 스타일로 삽입 → `requestCandidates(_:options:)` → `mainResults`(전체 후보) + `firstClauseResults`(문절 단위 후보)
- 1차는 `mainResults`만 사용(전체 변환). 문절 단위 부분 확정은 2차.
- Zenzai(신경망 변환)는 사용 안 함. 학습(`memoryDirectoryURL`)은 `.nothing`으로 시작.
- pre-1.0이므로 `.upToNextMinor`로 버전 고정.

## 3. 입력 파이프라인과 상태 머신

```
키 입력 ㅌ ㅗ ㅜ ㅋ ㅛ ㅜ
  → JamoComposer: 토, 우, 쿄, 우      (음절 경계 자동 판정)
  → KanaMapper:   とうきょう           (마크드 텍스트로 실시간 표시)
  → [Space] requestCandidates → 후보: 東京 / とうきょう / トウキョウ …
  → [Enter 또는 숫자키] 확정 → 앱에 커밋
```

상태: **empty** → **composing**(한글 버퍼 + 가나 프리뷰) → **selecting**(후보창 표시)

| 키 | composing | selecting |
|---|---|---|
| 한글 키 | 자모 추가, 가나 프리뷰 갱신 | 현재 후보 확정 후 새 조합 시작 |
| Space | 변환 시작 → selecting | 다음 후보 |
| Enter | 가나 그대로 커밋 | 현재 후보 커밋 |
| Esc | 조합 취소(버퍼 비움) | 변환 취소 → composing(가나로 복귀) |
| Backspace | 자모 1개 삭제 | 변환 취소 → composing |
| 숫자 1–9 | (자모 아님 → 커밋 후 통과) | 해당 후보 커밋 |
| ↑/↓ | — | 후보 이동 |
| `-` | ー 추가 | — |

- 마크드 텍스트(밑줄 조합 문자열)에는 **가나**를 표시한다(한글 아님). 오타를 즉시 확인할 수 있는 실시간 피드백이 이 설계의 핵심 안전장치다(자/쟈 등 발음이 같은 표기 구분 실수 대비).
- 매핑 불가능한 한글 음절(예: 별, 관)은 가나로 못 바꾼 채 한글 그대로 마크드 텍스트에 남긴다. 변환 시도 시 해당 부분은 무시하지 않고 그대로 통과시킨다. 사용자는 프리뷰에서 즉시 알아채고 백스페이스로 수정한다.
- 비(非)조합 키(영문, 숫자, 문장부호)는 조합 중이면 조합을 커밋한 뒤 통과. 단 `.`→`。`, `,`→`、` 로 매핑(일본어 입력기의 기본 동작).
- 보안 입력 필드(비밀번호)에서는 OS가 IME를 우회한다 — 모든 IME 공통, 대응 불가.

## 4. 매핑 사양

**원칙: 한글 1음절 = 가나 철자 1모라. 격음(ㅋㅌㅍ+ㅊ·ㅅ)=청음, 평음(ㄱㄷㅂㅈ)=탁음, 위치 무관.**
국립국어원 외래어 표기법은 비가역(어두/어중 구분, 장음 소실, ず=づ 병합)이라 채택하지 않는다. 로마지가 발음(Tokyo)이 아닌 철자(toukyou)를 치듯, 가나 철자에 충실하게 친다.

### 4.1 기본 음절표 (정규 표기)

| 행 | あ단 | い단 | う단 | え단 | お단 | 요음 (ゃ/ゅ/ょ) |
|---|---|---|---|---|---|---|
| あ | 아=あ | 이=い | 우=う | 에=え | 오=お | 야=や 유=ゆ 요=よ |
| か | 카 | 키 | 쿠 | 케 | 코 | 캬 큐 쿄 |
| が | 가 | 기 | 구 | 게 | 고 | 갸 규 교 |
| さ | 사 | 시=し | 스 | 세 | 소 | 샤 슈 쇼 |
| ざ | 자 | 지=じ | 즈 | 제 | 조 | 쟈 쥬 죠 |
| た | 타 | 치=ち | 츠=つ | 테 | 토 | 챠 츄 쵸 |
| だ | 다 | 띠=ぢ | 뜨=づ | 데 | 도 | — |
| な | 나 | 니 | 누 | 네 | 노 | 냐 뉴 뇨 |
| は | 하 | 히 | 후 | 헤 | 호 | 햐 휴 효 |
| ば | 바 | 비 | 부 | 베 | 보 | 뱌 뷰 뵤 |
| ぱ | 파 | 피 | 푸 | 페 | 포 | 퍄 퓨 표 |
| ま | 마 | 미 | 무 | 메 | 모 | 먀 뮤 묘 |
| ら | 라 | 리 | 루 | 레 | 로 | 랴 류 료 |
| わ행 | 와=わ | — | — | — | 워=を | |

- **ん** = 받침 ㄴ. 간=かん, 간이=かんい vs 가니=かに (초성 ㅇ 덕분에 자동 구분 — 로마지 n' 불필요)
- **っ** = 받침 ㅅ. 삿포로=さっぽろ. 어말 받침 ㅅ도 っ(앗!=あっ!)
- **장음** = 철자 그대로. 토우쿄우=とうきょう, 오오사카=おおさか, 에이가=えいが. (우/오/이가 독립 음절이므로 특수 처리 로직 자체가 불필요)
- **ー** = `-` 키
- **조사** = 철자대로: 하=は, 헤=へ, 워=を
- う단 정규 표기는 표기법 습관을 따름: 스/즈/츠/뜨는 ㅡ, 나머지(쿠/구/누/후/부/푸/무/루/유)는 ㅜ

### 4.2 관용 별칭 (입력 허용 → 정규화)

| 별칭 | 결과 | 근거(습관) |
|---|---|---|
| ㄲ행 (까끼꾸께꼬, 꺄뀨꾜) | か행 | 홋**까**이도 |
| ㄸ (따/떼/또) — 띠/뜨 제외 | た행 | |
| ㅃ행 (빠삐뿌뻬뽀, 뺘쀼뾰) | ぱ행 | 잇**빠**이 |
| ㅆ행 (싸씨쎄쏘) — **쓰=つ 예외** | さ행 | 표기법의 쓰=つ |
| ㅉ행 (짜쮸쬬), 찌=ち, **쯔=つ** | ちゃ행 | 곤니**찌**와, **쯔**꾸르, ~**짱** |
| 받침 ㄱ/ㅂ/ㄷ | っ | 혹카이도, 잇파이 |
| 받침 ㅇ/ㅁ | ん | 망가=まんが, 돔부리=どんぶり |
| ㅜ↔ㅡ (う단, 충돌 없는 곳) | 동일 취급 | 수=스=す, 흐=후=ふ, 주=즈=ず, 크=쿠=く 등 |
| 차/추/초 | ちゃ/ちゅ/ちょ | ㅊ에는 다른 배정이 없어 챠/츄/쵸와 동일 취급 (단, 츠=つ는 그대로) |

주의: **자↔쟈는 별칭이 아니다** — 자=ざ, 쟈=じゃ로 반드시 구분 (조/죠, 주/쥬 동일). §4.4 참고.

- 된소리는 **청음 별칭**이다(촉음 삽입이 아님). 바까=ばか(○), ばっか(×). 촉음은 항상 받침으로 친다: 홋까이도 = 받침ㅅ(→っ) + 까(→か).
- ㄸ+ㅣ/ㅡ(띠/뜨)만 희귀 가나 ぢ/づ에 특수 배정. ぢ/づ는 た행 탁음이므로 ㄷ 계열에 두는 것이 체계적으로도 맞다.

### 4.3 확장 가타카나용 음절 (일본어에 없는 한글 음절 활용)

| 한글 | 가나 | | 한글 | 가나 |
|---|---|---|---|---|
| 티 | てぃ(ティ) | | 화 | ふぁ(ファ) |
| 디 | でぃ(ディ) | | 휘 | ふぃ(フィ) |
| 투 | とぅ(トゥ) | | 훼 | ふぇ(フェ) |
| 두 | どぅ(ドゥ) | | 훠 | ふぉ(フォ) |
| 위 | うぃ(ウィ) | | 웨 | うぇ(ウェ) |

(가타카나 표기 선택은 후보창에서. ヴ 계열은 비목표)

### 4.4 남은 마이너 규칙

- 자=ざ vs 쟈=じゃ (조/죠, 주/쥬 동일): 한글 표기로는 구분되지만 현대 한국어 발음이 같아 오타 최다 예상 지점 → 실시간 가나 프리뷰가 완화책. 규칙 자체는 결정적.
- 두=ドゥ와 づ=뜨, ず=즈/주는 서로 다른 음절이므로 충돌 없음.

## 5. IMKit 셸 구현 방침

- 조합 표시는 항상 `setMarkedText` (고전 방식, 앱 호환성 최대). `insertText`는 `NSRange(location: NSNotFound, length: 0)`.
- Swift 6 strict concurrency와 IMKit은 상극(헤더에 @MainActor/nullability 없음) → 타깃 전체 `@MainActor` 기본 격리 + 컨트롤러 오버라이드 `nonisolated` 패턴 (vChewing 저자 Shiki Suen의 2026 가이드라인). 필요 시 vChewing/IMKSwift 래퍼 채택 검토.
- macOS 15.2류 리그레션 대비: `sender`를 `responds(to:)` 확인 후 `IMKTextInput` 캐스팅하는 방어 코드.
- 로깅은 os_log + Console.app (print는 안 보임). NSLog 남발 금지(개인정보 = 타이핑 내용).

## 6. 개발 루프와 설치

```
빌드 → ~/Library/Input Methods/Hangulji.app 복사 → killall Hangulji
→ 입력 소스 재선택 (최초 설치 시 1회 로그아웃/로그인 필요할 수 있음)
```

- 위 과정을 `scripts/install-dev.sh`로 자동화
- 서명: 개인용이므로 ad-hoc/개발 서명. 스테일 복사본이 서명 오류를 일으키면 기존 앱 수동 삭제(hangeul_ime에서 확인된 함정)
- 참고 코드베이스: ensan-hcl/macOS_IMKitSample_2021(부트스트랩), AlienKevin/hangeul_ime(한글 조합·백스페이스), azooKey-Desktop(엔진 연결·후보창), macSKK(상태머신 구조·GPL이므로 참고만)

## 7. 테스트 전략

- **HanguljiCore 유닛테스트가 품질의 핵심.** 테이블 주도 골든 테스트:
  - §4.1 기본표 전수 + 요음 전수
  - 엣지: 간이/가니, 받침 재해석, 촉음(받침 ㅅ/ㄱ/ㅂ/ㄷ), ん 별칭(ㅇ/ㅁ), 장음 시퀀스, 별칭 정규화(까/쓰/쯔/찌), 띠/뜨, 확장 가타카나 음절, 매핑 불가 음절 통과, 조합 중 백스페이스(자모 단위 복원)
  - 문장 단위: 토우쿄우니이키마스 → とうきょうにいきます 급 케이스 10+개
- **셸 수동 테스트 매트릭스**: TextEdit, Safari(검색창), Terminal, VS Code(Electron), Spotlight
- **변환 품질**: 엔진 신뢰(실전 검증됨). ComposingText 연동 통합 테스트 소수만.

## 8. 리스크

| 리스크 | 대응 |
|---|---|
| IMKit이 OS 릴리스마다 깨질 수 있음 (15.2 선례) | 방어적 코딩, 최신 포인트 릴리스에서 조기 테스트 |
| AzooKeyKanaKanjiConverter pre-1.0 API 변동 | `.upToNextMinor` 고정, 어댑터 한 겹 |
| 자/쟈류 표기 혼동으로 인한 오타 | 실시간 가나 프리뷰(마크드 텍스트) |
| 최초 등록 안 됨/회색 처리 | ConnectionName 패턴 준수, 로그아웃/로그인 안내 |

## 9. 참고 자료

- https://github.com/azooKey/AzooKeyKanaKanjiConverter (변환 엔진)
- https://github.com/azooKey/azooKey-Desktop (동일 엔진의 실전 macOS IME)
- https://github.com/ensan-hcl/macOS_IMKitSample_2021 (미니멀 IMKit 샘플)
- https://github.com/AlienKevin/hangeul_ime (한글 조합 Swift IME)
- https://github.com/mtgto/macSKK (모던 Swift IME 구조, GPL — 참고만)
- https://shikisuen.medium.com/macos-input-method-development-guidelines-for-2026-5123461fa53b
- https://github.com/Hanjp-IM/ibus-hanjp (Linux 선례)
- https://www.ltool.net/hangul-pronunciation-input-to-japanese-hiragana-katakana-converter-in-korean.php (매핑 관례 선례)
- 국립국어원 외래어 표기법 일본어 표 (채택하지 않는 이유의 근거): https://ko.wikisource.org/wiki/국립국어원_외래어_표기법/일본어
