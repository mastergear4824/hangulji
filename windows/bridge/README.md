# 한글지 브리지 (Windows 2단계)

## 개요

1단계([windows/README.md](../README.md))가 Google 일본어 입력의 커스텀 로마자 테이블이라면,
2단계 브리지는 **시스템 기본 MS-IME를 테이블 교체 없이 그대로** 쓰는 상주 프로그램이다.
`hangulji-bridge.exe`가 2벌식 키입력을 가로채 MS-IME 로마자 키스트림으로 재주입하고,
가나 조합·한자 변환·후보 선택은 전부 MS-IME가 담당한다.

변환 표는 `spec/mapping.tsv`에서 생성되며(§ 재생성), 로마자 철자는 훈령식 우선 +
MS-IME 확장(si·ti·tu·zi·di·du / thi·dhi·twu·dwu / fa·fi·fe·fo / wi·we / ん=nn / っ=xtu)이다.

## 빌드

    cargo build --release
    # 산출물: target/release/hangulji-bridge.exe

GitHub Actions(windows-bridge 워크플로)가 같은 명령으로 빌드한 서명 없는 exe를
아티팩트로 올린다. 서명이 없으므로 실행 시 SmartScreen 경고가 뜰 수 있다.

## 사용

1. Windows 일본어 IME(MS-IME)를 켜고 ひらがな 모드 + 로마자 입력으로 둔다
2. `hangulji-bridge.exe` 실행 (콘솔 창 유지)
3. 아무 앱에서 2벌식 위치로 타이핑: xhdnzydn(토우쿄우) → とうきょう → Space → 東京
4. **Ctrl+Space**로 브리지 켬/끔 토글 (영문 입력이 필요할 때 끈다)
5. 종료는 콘솔 창에서 Ctrl+C

## 한계 (정직하게)

- **실기기 미검증**: Windows 기기가 없어 실행 검증을 못 했다. CI의 exe 빌드 +
  변환 로직 conformance(픽스처 44케이스, 로마자→가나 오라클 왕복)까지가 현재
  책임 범위다(설계 §5.4·§7 SP5). MS-IME가 이 로마자 철자 전부를 기본 설정에서
  수용하는지, Shift 상태 복원 주입이 실제로 동작하는지가 실기기 1순위 확인 항목
- **관리자 권한 창·보안 데스크톱(UAC·로그인 화면) 주입 불가** — 저수준 훅의 구조적 한계
- **훅 타임아웃**: 시스템이 느릴 때 OS가 훅을 제거할 수 있다(LowLevelHooksTimeout).
  입력이 원래 키로 돌아가면 브리지를 재실행한다
- **매핑 불가 음절은 로마자·라틴 키가 그대로 샌다**: 별(quf) → っうf 상당 (1단계의
  "っuf"와 동급). 오타를 바로 알아챌 수 있는 동작으로 활용
- **백스페이스**: 아직 화면에 나가지 않은 대기 키(pending)만 브리지가 취소하고,
  화면에 이미 조합된 가나의 삭제는 MS-IME 기본 동작이다. 빠른 타이핑 중에는
  대기 판정이 한 키 늦을 수 있다
- Ctrl/Alt 동반 키(단축키)는 변환하지 않고 통과시킨다

### 실기기 리스크 체크리스트 (최종 리뷰 실측)

실기기가 없어 아래는 전부 코드 리뷰로만 확인한 추정이다. 온디바이스 검증 시
우선순위 순서대로 확인한다.

① **MS-IME의 `nn` 경계 파싱이 온디바이스 검증 1순위** — 브리지는 ん을 항상
   `nn`으로 내보낸다(간이 예: がんに류 → `gannni`). 이 경계 해석을 테스트
   오라클(`ROMAJI_TO_KANA`)이 아니라 실제 MS-IME가 어떻게 소비하는지는 아직
   확인 못 했다. 오라클과 실제 IME 동작이 갈리면 화면에 잘못된 가나가
   조합되는데도 브리지·CI 어느 쪽도 감지하지 못하는 무음 손상이 가능하다.
② **US-QWERTY VK 가정 미검증** — `map_char`/`char_to_vk`는 VK 코드가 미국
   QWERTY 물리 배열과 일치한다고 가정한다. JIS 배열이나 한국어 물리 자판에서
   VK 코드가 다르게 나올 가능성은 실기기 확인 전까지 미검증이다.
③ **Ctrl+Space가 Windows 자체 IME 토글과 충돌할 수 있다** — 일부 환경에서
   Windows/MS-IME 자체도 Ctrl+Space를 IME 켬/끔 단축키로 쓴다. 겹치면 브리지
   토글과 IME 토글이 동시에 반응해 예상과 다른 상태가 될 수 있다. 충돌 시
   Windows 설정(시간 및 언어 → 입력 → 고급 키보드 설정 → 언어 표시줄 핫키)에서
   해당 단축키를 변경해 회피한다.
④ **고속 타이핑 시 GetAsyncKeyState 모디파이어 레이스** — `key_down()`은 훅
   프로시저 호출 시점에 `GetAsyncKeyState`를 폴링한다. Shift·Ctrl을 매우
   빠르게 누르고 뗄 때 폴링 시점과 실제 물리 상태 사이에 경합이 생겨 판정이
   한 이벤트 어긋날 수 있다(위 `PENDING_LEN` 구식 값 리스크와 같은 종류).
⑤ **대문자 raw-echo는 Shift 랩 주입으로 동작한다(이번 수정)** — Shift+O·P 등
   TSV에 몸통이 없는 대문자 배정이 raw로 새는 열화 경로에서, `char_to_vk`가
   해당 문자를 자체 Shift-down/up으로 감싸 주입해 앱이 대문자 그대로 받도록
   한다(이전에는 `unreachable!()` 패닉으로 워커 스레드가 죽어 훅이 키보드를
   계속 삼켰다 — 수정 완료). 이 Shift 랩이 실제 MS-IME·앱 조합에서 대문자를
   정확히 재현하는지는 여전히 온디바이스 확인 대상이다.

## 테스트 (어느 OS에서나)

    cargo test
    # translator 유닛 4건 + spec/fixtures conformance 3건
    # conformance는 spec/fixtures/kana.json 전 케이스를 순회한다.
    # composition.json은 무패닉 스모크만 — 브리지에는 자모 음절 조합기가 없어
    # 한글 음절 목록 검증이 구조적으로 불가하고(호스트 IME에 로마자를 흘리는 구조),
    # 받침 재해석 의미론은 가나 레벨 trace 테스트로 고정한다 (1단계 선례와 동일)

## 재생성

매핑 규칙 변경 후 (저장소 루트에서):

    swift spec/generators/gen-bridge-table.swift

산출물 `src/table_generated.rs`는 수기 수정 금지 — core CI가 최신성(재생성 후 diff 0)을 검사한다.
