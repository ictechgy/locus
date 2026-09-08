# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-08 (검토 수정 세션 종료 직후) · **기준**: `main` == `origin/main` (`00701bb`)
- **상태**: 2026-09-08 전체 검토의 수정 필요 8건(P1 2·P2 4·P3 2) **전부 수정·머지 완료**
  (PR #2 rebase-merge, CI 그린 4m21s — 디버그 빌드 + 테스트 전부 + 릴리스 빌드).
  공개 저장소 https://github.com/ictechgy/locus · 태그는 아직 `v0.3.0` (이번 수정
  전부 CHANGELOG `Unreleased` — v0.3.1 승격 대기).
- 로컬 경로 `/Users/jinhongan/Desktop/Z_Workspace/locus`.

## 이번 세션 결과 (믿어도 되는 상태)

### 수정 8건 (상세 원인·재현은 아래 "원본 검토 기록"과 PR #2 참조)

1. **P1 부분 맵 거부** — `MapStore.load`가 5개 파일 전부 + 포맷 버전 + index/배열
   수 일관성 검증(불일치 시 재크롤 안내 오류). `writeAtomic` 교체 실패 전파
   (목적지에 디렉터리가 있어도 성공 보고하던 것 수정). MapStoreTests 6종.
2. **P1 기준계 통일** — `affectedTests`가 git을 **맵 sourceRoot가 속한 저장소**에서
   실행(러처 밖 `--out` 호출 시 "Not a git repository"로 죽던 것 수정). 명시
   `--files`도 같은 저장소 기준 정규화(형제 모듈 오탐 제거), `files=[]`는 git
   폴백 없음. 테스트 3종.
3. **P2 상수표 let 전용** — `var`(static/인스턴스) 리터럴 초기화는 상수표 제외.
   미해석 참조는 부채로 잔류.
4. **P2 빈/미해석 식별자 = 부채** — `.accessibilityIdentifier("")`와 미해석 UIKit
   대입이 missing-identifiers에 잡히도록(UIKit assigned 판정을 상수 해석 후로
   이연 — `RawHit.assignedRoot`).
5. **P2 CLI 옵션 문법** — `LocusCore/Arguments.swift`(CommandGrammar)로 이전,
   값 누락·빈 `--name=`·unknown·positional 개수 오류 전부 사용 오류 exit 2
   (기존엔 `--out` 값이 문자열 "true"가 돼 `./true/`에 맵 생성). ArgumentsTests 6종.
6. **P2 심볼릭 링크 skip** — 디렉터리 링크가 조상 루프로 크롤 전체 사망(Cocoa 256/
   POSIX 20)하거나 파일 이중 수집하던 것 방지. 크롤 루트 자체는 링크 허용.
7. **P3 MCP 프레임 상한** — `FrameAssembler` 32MiB 상한(초과 시 JSON-RPC 오류 +
   연결 유지), 청크당 1회 버퍼 정리. 테스트 5종.
8. **P3 프로세스 타임아웃** — 공유 `ProcessRunner`(동시 drain 유지 + 하드
   타임아웃/SIGTERM). git 60s, idb 120s. /bin/sleep 기반 타임아웃 테스트.

테스트: 53 → 73개 전부 그린. 신규 파일: `Arguments.swift`, `ProcessRunner.swift`,
테스트 3개(MapStore·Arguments·ProcessRunner).

### 이 세션이 밝힌 환경 사실 (에이전트 셸 기준 — 재발 방지)

- **에이전트 셸에서 로컬 swift build/test 불가**: CLT 컴파일러/SDK는 이제 정상
  (사용자가 복구함 — 검토 세션의 "로컬 빌드 가능" 기록은 사실). 그러나 새 SPM
  (swift-build 재작성)이 내부적으로 쓰는 경로들이 샌드박스에 막힘:
  `~/Library/Caches/org.swift.swiftpm`(매니페스트 캐시), `~/Library/Caches/swift-build/Cache.db`,
  SPM 내부 sandbox-exec, `.build` 내부의 git 쓰기(의존성 클론). 시도한 우회
  (`--disable-sandbox`, `--cache-path`, 홈 스트래치, 수동 클론, GIT_TEMPLATE_DIR,
  CLANG_MODULE_CACHE_PATH)로 swift-syntax 체크아웃까지는 도달하지만 모듈 빌드
  단계(`LocusCore.build/output-file-map.json` I/O code 1)에서 계속 사망.
  **사용자 터미널에서는 `swift test` 정상 동작** — 검토 세션이 그렇게 돌렸음.
- **CI 로그 블라인드 해소**: CI가 컴파일/테스트 오류를 `::error::` 어노테이션으로
  남기게 워크플로 갱신(커밋 `4d3716e`). 어노테이션은
  `gh api repos/ictechgy/locus/check-runs/<job-id>/annotations`로 읽을 수 있다.
  이걸로 `String(data:as:)` 오류를 한 번에 잡음 — 앞으로 CI 왕복이 저렴해짐.
- git 신원·upstream 제약은 이전 기록 그대로: 커밋마다 GIT_AUTHOR_NAME/EMAIL
  환경변수(Coden <ictechgy@gmail.com>), `git push origin <branch>:<branch>`.

## 다음 세션 할 일 (우선순위)

### 0. v0.3.1 릴리스 (권장 — 수정이 쌓여 있음)
CHANGELOG `Unreleased` 승격 + `MapFormat.releaseVersion` "0.3.1" + README
트랜스크립트 재실행 확인(사용자 터미널에서) + `git tag v0.3.1` + 푸시.
릴리스 체크리스트는 AGENTS.md.

### 1. 공개 후 유통 (기획서 "첫 공개 전략" — 해자 축 ②③)
- **데모 GIF**: 시뮬레이터 버그 발견 → `where_is` → 수정 → `affected_tests` 재실행.
- **커뮤니티**: Arbigent·XcodeBuildMCP·AccessibilitySnapshot에 `match_snapshot`
  interop 소개. HN/Reddit은 GIF 후.

### 2. 검증 저변 확대 (해자 축 ①)
- 오픈소스 iOS 앱 2~4개 추가 크롤(firefox-ios/Wikipedia급 UIKit 대형 포함) →
  README "실전 검증" 표 갱신. **주의: 이번 let 전용화로 상수 문화 저장소에서
  `static var` 식별자 패턴이 있으면 미해석 잔차로 내려간다 — 실측 시 잔차
  증가분이 그 패턴의 실제 빈도 측정이 된다.**

### 3. 이후 (v1.x 후보)
- 심볼 앵커 정밀화(extension/조건부 컴파일 → IndexStoreDB), 화면 경계 유추,
  identifier 코드젠, Android/Kotlin 확장.
- 미수정 관찰: ProcessRunner의 SIGTERM 무시 자식 잔류(경로는 주석에 기록),
  `crawlFile` 4-튜플 반환(구조체화 언젠가), 크롤+스캔 디렉터리 2회 순회.

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 백그라운드 + 폴링 필수.
- **DemoApp에 직접 `git init` 금지** — `Scripts/setup-demo.sh`만. 데모 잔여는
  커밋 전 정리(`rm -rf Examples/DemoApp/.git Examples/DemoApp/.locus` +
  `git checkout -- Examples/DemoApp`).
- **경로 기준계** — affectedTests의 git은 맵 sourceRoot가 속한 저장소 기준.
  sourceRoot == repoRoot면 prefix `""`, 중첩이면 하위 경로, 저장소 밖이어야
  nil(접미사 폴백 — 명시 files 포함 전 경로 동일 정규화). 회귀 테스트 4종
  (nested·repoRoot·map-repo-wins·explicit-frame).
- **맵 로드 검증** — 5개 파일 전부 + 버전 + 세대 일관성(index counts). 부분
  맵은 즉시 오류. `writeAtomic` 우회 금지(교체 실패 전파됨).
- **버전 단일 소스**: `MapFormat.releaseVersion`(현재 "0.3.0", Unreleased 있음).
- **CLI 옵션은 전부 값 옵션** — 문법은 `LocusCore/Arguments.swift`. 새 옵션 추가
  시 CommandGrammar에 등록.
- **idb는 선택 의존** — `--udid` 선행 `-` 가드, 타임아웃 120s. env 경유 PATH
  조회가 유일한 경로.
- **셸 cwd 잔류 주의** — 항상 `cd /Users/jinhongan/Desktop/Z_Workspace/locus &&`.
- **GitHub**: `gh` 인증됨(계정 `ictechgy`). remote `origin` =
  https://github.com/ictechgy/locus. 푸시·릴리스는 승인 게이트 아님.

## 원본 검토 기록 (2026-09-08, 수정 전 — 맥락 보존)

- 기준 `main@e967fb4`에서 8건 실측 재현으로 확인(부분 맵 exit 0 / repo 밖
  git 사망 / static var high-confidence / 빈 ID·미해석 대입 missing=[] /
  `--out` 누락 시 `./true/` 생성 / 디렉터리 symlink Cocoa 256·POSIX 20 /
  MCP 무제한 버퍼 / git·idb 무타임아웃). 증거 로그는 휘발성(/tmp).
- 검증 명령(사용자 터미널): `swift test --skip-update --disable-automatic-resolution
  --scratch-path <path>` — 전역 캐시에서 오프라인 materialize. 당시 53 tests
  그린(Swift 6.4/Xcode 27 beta).

## 참조

- 이번 수정 상세: PR #2 (https://github.com/ictechgy/locus/pull/2) ·
  이전 리뷰 패스: PR #1
- 기획서: `기획서.md` · 에이전트 지침: `AGENTS.md` · 사용법·실전 검증:
  `README.md` · 버전 이력: `CHANGELOG.md`
- 실전 검증 대상 클론: /tmp/breadcrumb-p0/element-x-ios (휘발성 — 필요시 재클론)
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검) — 화면 귀속 접점은
  기획서 차별화 표에 명시.
