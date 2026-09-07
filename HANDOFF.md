# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-06 (공개 세션 종료 직후) · **기준**: `main` == `origin/main`
- **상태**: **공개됨** — https://github.com/ictechgy/locus · 태그 `v0.3.0` 푸시 ·
  CI 첫 실행 그린(5m02s, macos-14: debug 빌드 → 50 테스트 → release 빌드).
  토픽 등록(swift·ios·accessibility·mcp·model-context-protocol·swift-syntax·
  static-analysis·ui-testing). 로컬 경로 `/Users/jinhongan/Desktop/Z_Workspace/locus`.
- **유의**: 이 파일의 개정은 **미커밋** 상태로 남는다(세션 종료 시점의 셸 문제로
  커밋 불가). 다음 세션의 첫 커밋에 포함할 것.

## 직전 세션 전체 요약 (믿어도 되는 상태)

한 세션에서 리뷰 → P0 → P1 → P2 → 개명 → 공개까지 진행했다.

### 코드 리뷰 (구조·성능·보안·정확성)
- 결함 3건 수정(커밋 `033d900`): git option 인젝션 가드(`--ref --output=...` 거부 +
  `--end-of-options`), GUI 앱 최소 PATH 대응(`/usr/bin/git` 우선),
  `--help`·MCP 버전 테스트의 버전 단일 소스화.
- 기록만 한 관찰(미수정): 심볼 앵커는 extension 선언에서 타입명 미획득,
  `Glob` `**` 중첩의 이론적 백트래킹, MCP 무제한 라인 버퍼, 심볼릭 링크 순환 무방어.

### P0 — 실전 검증 (element-x-ios, Swift 1,385파일) → v0.2 스코프 (커밋 `5902e57`)
- **치명 발견**: 식별자 콜사이트 158곳 중 리터럴 1곳 — 실전은 상수 문화.
  상수 해석 없이 elements 0개.
- `ConstantTable`: struct/enum 멤버 리터럴, String raw-value enum(암시 케이스명),
  `static let ns = Type()` 네임스페이스 별칭, 백틱 멤버, 레이블드 인자
  (`accessibilityIdentifier:` 파라미터), 테스트의 상수 참조까지 역색인.
  충돌 선언은 항목 버림(모호 > 오답).
- 노이즈 실측·조정: orphan 243→6(UI-쿼리 위치로 판정 제한 — 형태만으론 95% 노이즈),
  missing 1,349→424(비인터랙티브 종류 제외).
- 성능: 릴리스 크롤 4.6초. 병렬화 불필요. 정밀도: 표본 전부 정확, 잔차 12곳은
  정적 불가능 형태(함수형 상수, 계산 속성+switch — `session_verification-*` 사례).
- README "실전 검증 (P0)" 섹션에 수치 공개 상태.

### P1 — v0.3 동적 스냅샷 (커밋 `76a78e1`)
- `Snapshot.swift`: 덤프 파싱(배열/`{elements:[]}` + idb `AX*` 필드 별칭),
  매처(identifier 직매칭 high / 고유 라벨 medium·kind 불일치 low / 중복 라벨 매칭
  안 함), 잔차(화면상 미식별 = 자동화 부채, 미매칭 id, unseen, 커버리지).
- CLI `snapshot <dump.json|-> [--udid]`(idb 캡처는 선택 의존 — 이 머신에 idb 없어
  `--udid` 경로는 미검증), MCP 5번째 툴 `match_snapshot(dump)` = 에이전트 interop.

### 개명 breadcrumb → locus (커밋 `4d3bbff`, 사용자 결정 2026-09-06)
- 검색 유니크성 > 서사 정합. 패키지·모듈(LocusCore/LocusCLI)·바이너리·
  맵 디렉터리 `.locus/`·MCP serverInfo·타입(LocusMap/LocusError/locusJSON)·문서 전면.
  태그라인: "locus — where every UI element lives in source". **이름 최종.**
- 로컬 폴더도 `Z_Workspace/locus`로 변경 — 예전 세션의 셸 앵커는 구 경로를
  가리켜 해당 세션에서 셸이 죽었던 것. 새 세션은 새 경로에서 열면 무관.

### 공개 (커밋 `f7a6017`, `e34f4af`)
- CI의 `Xcode_15.4.app` 고정 제거(현 러너 이미지에 없어 첫 CI 실패 예방).
  `ictechgy/locus` 퍼블릭 생성 + main + v0.3.0 태그 푸시, CI 그린, 토픽 등록,
  README 클론 URL 확정. 사소: `actions/checkout@v4` Node 20 지원 중단 경고 —
  언젠가 `@v6`으로 올리면 사라짐(기능 영향 없음).

## 다음 세션 할 일 (우선순위)

### 0. 이 파일 커밋·푸시
위 유의 사항 참조. `docs: handoff refresh after first public release` 정도면 충분.

### 1. 공개 후 유통 (기획서 "첫 공개 전략" 실행 — 여기서부터가 해자 축 ②③)
- **데모 GIF**: 에이전트가 시뮬레이터에서 버그 발견 → `where_is`로 소스 즉시 오픈 →
  수정 → `affected_tests`로 관련 3개만 재실행 → 통과. 전체 UI 테스트 실행과의
  소요·토큰 대비를 같은 화면에. 시뮬레이터 녹화 + MCP 세션 트레이스로 제작 가능.
- **커뮤니티 접근**: Arbigent·XcodeBuildMCP·AccessibilitySnapshot 쪽에
  `match_snapshot` interop 어댑터 소개. HN/Reddit(iosProgramming)은 GIF 확보 후.
- Homebrew tap·SPM 원라인 설치는 수요 신호 확인 후(현재는 clone+build).

### 2. 검증 저변 확대 (해자 축 ① — 정밀도 데이터 축적)
- 오픈소스 iOS 앱 2~4개 저장소 추가 크롤(UIKit 위주 대형 앱 하나 포함 권장 —
  firefox-ios/Wikipedia급) → README "실전 검증" 표에 정밀도·재현율·크롤 시기 추가.
- 새 패턴 발견 시 먼저 실패하는 테스트(AGENTS.md 관습) → ConstantTable/Visitor 확장.

### 3. 이후 (v1.x 후보, 우선순위 미정)
- 심볼 앵커 정밀화: extension/조건부 컴파일 → 이후 IndexStoreDB
- 화면 경계 유추(내비게이션 구조, confidence 표기), identifier 코드젠,
  Android/Kotlin 확장(제작자 크로스플랫폼 자산)
- MCP 라인 버퍼 상한, 심볼릭 링크 순환 가드(리뷰 관찰 반영)

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 백그라운드 실행 + 폴링 필수.
  (AGENTS.md "명령" 섹션에도 경고 있음)
- **DemoApp에 직접 `git init` 금지** — 부모 저장소 gitlink 회귀(커밋 `243da0a`).
  git 데모는 `Scripts/setup-demo.sh`만. 데모 잔여 상태(dirty 파일·내부 git·`.locus/`)는
  커밋 전에 반드시 정리: `rm -rf Examples/DemoApp/.git Examples/DemoApp/.locus` +
  `git checkout -- Examples/DemoApp`.
- **경로 기준계** — 요소는 sourceRoot 상대, git은 저장소 루트 상대. 비교는 반드시
  `repoRelativePrefix` 정렬 후. 회귀 테스트:
  `testNestedSourceRootAvoidsCrossModuleFalsePositives`.
- **버전 단일 소스**: `MapFormat.releaseVersion`(현재 "0.3.0"). CLI·MCP·도움말 전부 파생.
- **상수 해석 경계**: 타입 이름을 중첩 경로 없이 키로 씀 — 다른 타입이 같은
  이름+멤버를 가지면 해석 생략(README "정직한 한계" 기록됨).
- **orphan은 UI-쿼리 위치 한정** — 형태 기반 판별은 실전 노이즈 95%(P0 실측).
- **idb는 선택 의존** — 코어는 파일/stdin 덤프로 성립. `--udid` 경로는 idb 설치 후
  수동 검증 필요(이 머진 미설치).
- **셸 cwd 잔류 주의** — 항상 `cd /Users/jinhongan/Desktop/Z_Workspace/locus &&`부터.
  직전 세션에서 Examples/DemoApp에 남아 `ls .build`가 비어 보이는 함정에 걸림.
- **GitHub**: `gh` 인증됨(계정 `ictechgy`). 리모트 `origin` =
  https://github.com/ictechgy/locus. 푸시·릴리스는 더 이상 승인 게이트 아님(이미 공개).

## 참조

- 기획서(차별화·이름 결정·첫 공개 전략): `기획서.md` · 에이전트 지침: `AGENTS.md` ·
  사용법·실전 검증 수치: `README.md` · 버전 이력: `CHANGELOG.md`
- 실전 검증 대상 클론: /tmp/breadcrumb-p0/element-x-ios (휘발성 — 필요시 재클론)
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검) — 부검 결과의 화면
  귀속에 locus가 쓰이는 접점은 기획서 차별화 표에 명시.
