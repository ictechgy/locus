# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-08 (v0.3.1 릴리스 직후) · **기준**: `main` == `origin/main`
- **상태**: **v0.3.1 릴리스 완료** — 태그 + GitHub Release
  (https://github.com/ictechgy/locus/releases/tag/v0.3.1). 두 차례 코드 검토의
  수정 전부 반영(PR #1·#2, 테스트 53→73, CI 그린). 이번 세션에서 할 일은
  아래 없음 — **다음 세션이 아래 1·2번부터 시작**한다.
- 로컬 경로 `/Users/jinhongan/Desktop/Z_Workspace/locus`.

## 다음 세션 할 일 (우선순위 순)

### 1. 데모 GIF 제작 (유통의 선행 조건 — 여기서부터)

기획서 "첫 공개 전략"의 시나리오를 30초 안에:
에이전트가 시뮬레이터에서 버그 발견 → `where_is`로 소스 즉시 오픈 → 수정 →
`affected_tests`로 관련 3개만 재실행 → 통과. **전체 UI 테스트 실행과의
소요시간·토큰 대비**를 같은 화면에.

제작 재료:
- 입력: `Examples/DemoApp` + `Scripts/setup-demo.sh`(임시 내부 git 생성 —
  DemoApp에 직접 git init 금지). README Quickstart 트랜스크립트가 그대로 대본.
- 녹화: `xcrun simctl io booted recordVideo out.mp4` (시뮬레이터) + 터미널/
  에디터 화면. MCP 세션 트레이스(`locus mcp` + where_is/affected_tests 호출)를
  보여주면 "에이전트 연동" 스토리가 같이 전달됨.
- GIF 변환 후 README 상단 + 릴리스 노트 첨부.
- 주의: idb는 이 머신에 없음(`--udid` 경로 미검증) — 덤프 파일 기반으로.

### 2. 커뮤니티 접근 (GIF 확보 후)

- **Arbigent**·**XcodeBuildMCP**·**AccessibilitySnapshot** 쪽에 `match_snapshot`
  interop 소개 — "에이전트가 자기 도구로 뽑은 덤프를 locus가 소스로 되돌려
  준다"는 어댑터 스토리. 이슈/PR보다는 사용 사례 시연 링크(데모 GIF)와 함께.
- HN / Reddit(r/iosProgramming)은 GIF 확보 후. 과장 없이 실측 수치
  (element-x-ios 1,385파일·크롤 4.6초·표본 정밀도) 위주로.
- Homebrew tap·SPM 원라인 설치는 수요 신호(이슈·스타) 확인 후 — 현재는
  clone + `swift build -c release`.

### 3. 검증 저변 확대 (해자 축 ① — 정밀도 데이터 축적)

- 오픈소스 iOS 앱 2~4개 추가 크롤. 권장: **firefox-ios**(UIKit 위주 대형),
  **wikipedia-ios**, 필요시 element-x-ios 재검증(/tmp 클론은 휘발 —
  재클론 필요).
- 각각 측정해 README "실전 검증" 표에 추가: 식별자 콜사이트 수·리터럴 비율·
  정밀도(표본 전수 확인)·재현율·잔차 분류·크롤 시간·**크롤 시기**.
- **v0.3.1 영향 실측**: 상수 해석이 let 전용이 됐으므로 `static var` 식별자
  패턴이 있는 저장소는 미해석 잔사가 늘어남 — 증가분 = 그 패턴의 실제 빈도.
  잔차 증가가 크면 "경고 없는 var" 지원(예: var에 단일 대입만 있으면 해석)을
  실패하는 테스트부터 다시 검토할지 판단.
- 새 패턴 발견 시 관습대로 실패하는 테스트 먼저 → ConstantTable/Visitor 확장.

### 4. 이후 (v1.x 후보, 우선순위 미정)

- 심볼 앵커 정밀화: extension/조건부 컴파일 → 이후 IndexStoreDB
- 화면 경계 유추(내비게이션 구조, confidence 표기), identifier 코드젠,
  Android/Kotlin 확장(제작자 크로스플랫폼 자산)
- 남은 관찰: ProcessRunner의 SIGTERM 무시 자식 잔류(경로는 코드 주석에 기록),
  `crawlFile` 4-튜플 반환 구조체화, 크롤+스캔 디렉터리 2회 순회·테스트 파일
  2중 파싱(현재 병목 아님), Glob `**` 이론적 백트래킹.

## 환경 사실 (에이전트 셔넬 기준 — 재발 방지)

- **로컬 swift build/test**: **사용자 터미널에서는 정상 동작**(검증 세션이
  53테스트 그린). 에이전트 셸에서는 새 SPM(swift-build 재작성)의 내부 경로
  (SPM 캐시·sandbox-exec·.build 내부 git 쓰기)가 차단돼 불가 — 우회 시도
  전적은 프로젝트 메모리에. **에이전트 세션 검증은 CI로**(아래 패턴).
- **CI-as-runner 패턴**: 브랜치 push → `gh pr create` → CI 그린 확인 →
  `gh pr merge --rebase --delete-branch`. CI 로그 직접 다운로드는 차단
  (results-receiver 403)이지만 컴파일/테스트 오류를 `::error::` 어노테이션으로
  남기므로 `gh api repos/ictechgy/locus/check-runs/<job-id>/annotations`으로
  원인 파악 가능(워크플로 커밋 `4d3716e`).
- **git 커밋 신원**: 에이전트 셔넬에선 `.git/config`·`~/.gitconfig` 쓰기 차단.
  커밋마다 `GIT_AUTHOR_NAME="Coden" GIT_AUTHOR_EMAIL="ictechgy@gmail.com"
  GIT_COMMITTER_NAME="Coden" GIT_COMMITTER_EMAIL="ictechgy@gmail.com"` 환경변수.
  upstream 등록 불가 → `git push origin <branch>:<branch>` 형태.
- **셸 cwd 잔류 주의** — 항상 `cd /Users/jinhongan/Desktop/Z_Workspace/locus &&`부터.
  임시 파일은 `~/` 사용(/tmp·/var/folders 쓰기 차단).
- **GitHub**: `gh` 인증됨(계정 `ictechgy`). remote `origin` =
  https://github.com/ictechgy/locus. 푸시·릴리스는 승인 게이트 아님.

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 백그라운드 실행 + 폴링 필수
  (AGENTS "명령" 경고).
- **DemoApp에 직접 `git init` 금지** — `Scripts/setup-demo.sh`만. 데모 잔여
  상태는 커밋 전 정리: `rm -rf Examples/DemoApp/.git Examples/DemoApp/.locus` +
  `git checkout -- Examples/DemoApp`.
- **경로 기준계** — affectedTests의 git은 **맵 sourceRoot가 속한 저장소** 기준
  (러처 CWD는 저장소 밖 폴백). sourceRoot == repoRoot면 prefix `""`, 중첩이면
  하위 경로, 저장소 밖이어야 nil(접미사 폴백). 명시 `--files`도 동일 정규화,
  `files=[]`는 git 폴백 없음. 회귀 테스트 4종(AffectedTestsTests).
- **맵 로드 검증** — 5개 파일 전부 + 포맷 버전 + 세대 일관성(index counts).
  부분 맵 즉시 오류. `writeAtomic` 우회 금지(교체 실패 전파).
- **버전 단일 소스**: `MapFormat.releaseVersion`(현재 "0.3.1"). CLI·MCP·
  맵 tool 문자열 전부 파생. 릴리스 체크리스트는 AGENTS.md — 순서 중요:
  **CI 그린 확인 후 태그**.
- **CLI 옵션은 전부 값 옵션** — 문법은 `LocusCore/Arguments.swift`
  (CommandGrammar). 새 옵션은 문법에 등록 후 ArgumentsTests 확장.
- **상수 해석은 let 전용** — var는 재할당 가능성 때문에 제외(미해석 잔차).
  orphan 판정은 UI-쿼리 위치 한정(리터럴·상수 참조 동일 규칙).
- **idb는 선택 의존** — `--udid` 선행 `-` 가드·타임아웃 120s. env 경유 PATH
  조회가 유일한 경로(/usr/bin 표준 위치 없음 — GitDiff의 /usr/bin/git 우선과
  다른 이유). 이 머신에 idb 미설치.
- **서브프로세스는 ProcessRunner로** — 동시 drain + 하드 타임아웃(git 60s·
  idb 120s). 직접 Process 스폰 금지.

## 참조

- 이번 세션까지의 상세: PR #1·#2, CHANGELOG 0.3.1 섹션, GitHub Release v0.3.1
- 기획서(차별화·첫 공개 전략): `기획서.md` · 에이전트 지침: `AGENTS.md` ·
  사용법·실전 검증 수치: `README.md` · 버전 이력: `CHANGELOG.md`
- 실전 검증 대상 클론: /tmp/breadcrumb-p0/element-x-ios (휘발성 — 필요시 재클론)
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검) — 부검 결과의
  화면 귀속에 locus가 쓰이는 접점은 기획서 차별화 표에 명시.
