# HANDOFF — 다음 세션 인수인계

- **작성일**: 2026-09-07 (코드 검토·수정 세션 종료 직후) · **기준**: `main` == `origin/main`
- **상태**: 리뷰 패스 #2 머지 완료(PR #1 rebase-merge, CI 그린). 공개 저장소
  https://github.com/ictechgy/locus · 태그는 아직 `v0.3.0`(이번 수정은 미릴리스,
  CHANGELOG `Unreleased` 참조). 로컬 경로 `/Users/jinhongan/Desktop/Z_Workspace/locus`.
- **⚠ 이 머신 로컬 빌드 불가**: CommandLineTools가 깨짐 — 컴파일러 6.3.3인데 SDK의
  Swift 모듈이 6.3.2/6.1 산이라 `swift build`가 즉시 실패("this SDK is not supported
  by the compiler"). Xcode.app·대체 툴체인·swiftly 전부 없음. **해결: CLT 재설치
  (sudo 필요)** — `sudo rm -rf /Library/Developer/CommandLineTools && sudo
  xcode-select --install` 또는 softwareupdate. 그 전까지 검증은 CI로(아래 패턴).

## 직전 세션 전체 요약 (믿어도 되는 상태)

### 성능·보안·구조 검토 (PR #1, 커밋 `fa33f77`·`49a6b3a`·`dabdd13`)
- **정확성(유일한 결함)**: `locus crawl .`(sourceRoot == 저장소 루트)일 때
  `repoRelativePrefix`가 nil을 반환해 접미사 매칭으로 빠짐 → 형제 디렉터리의 같은
  이름 파일 변경이 오탐. 수정: sourceRoot == repoRoot면 prefix `""`(기준계 정렬)
  반환, 정렬된 기준계에선 정확 일치만. 회귀 테스트
  `testRepoRootSourceRootAvoidsCrossModuleFalsePositives`(교훈: 형제 파일은 **다른
  식별자**를 줘야 자기 요소가 정상 affected로 잡히는 것과 오탐을 구분 가능).
- **성능**: `SnapshotMatcher` 식별자/라벨 버킷 인덱싱, `affectedTests` Set/사전
  인덱싱 — 둘 다 O(N×M) → O(N+M), 출력 바이트 동일.
- **보안**: `--udid` 선행 `-` 가드(git ref 가드와 대칭). helpText USAGE에 `snapshot`
  추가(누락돼 있었음). 상수 참조 orphan 판정을 문자열 리터럴과 동일한 UI-쿼리
  위치 규칙으로(`let label = A11y.x`는 부채 아님).
- **구조**: JSON 인코더 옵션 `MapFormat.jsonFormatting` 단일 상수로 공유(결정적
  바이트 불변식 보호). README "정직한 한계"에 UIKit 크로스파일 missing 과다보고
  항목 추가.
- **기록만 하고 미수정**(v1.x 관찰 목록): git/idb 프로세스 타임아웃 부재, MCP
  무제한 라인 버퍼 + `removeSubrange` O(n²), Glob `**` 이론적 백트래킹, 심볼릭
  링크 순환 무방대, `crawlFile` 5-튜플 반환(구조체화 언젠가), 크롤+스캔 디렉터리
  2회 순회/테스트 파일 2중 파싱(현재 병목 아님).

### 이 세션이 밝힌 환경 사실 (재발 방지)
- **git 커밋 신원**: 에이전트 셸에선 `.git/config`·`~/.gitconfig` 쓰기가
  차단됨(`com.apple.provenance` 확장 속성 + HOME 경로 문제). 커밋마다
  `GIT_AUTHOR_NAME="Coden" GIT_AUTHOR_EMAIL="ictechgy@gmail.com"
  GIT_COMMITTER_NAME="Coden" GIT_COMMITTER_EMAIL="ictechgy@gmail.com"` 환경변수로.
  -u 없이 `git push origin review-fixes:review-fixes` 형태로(upstream 등록 불가).
- **CI가 유일한 테스트 러너**: 브랜치 push만으론 CI가 안 돌고 PR이나 main push에만
  트리거. 패턴: 브랜치 push → `gh pr create` → CI 그린 확인 →
  `gh pr merge --rebase --delete-branch`.
- **CI 로그 직접 다운로드 차단**(results-receiver 프록시 403). 실패 원인은
  `gh api repos/ictechgy/locus/check-runs/<job-id>/annotations` 어노테이션으로
  부분 확인 가능(테스트 상세는 안 나옴 — 테스트 설계를 정밀하게 해야 반복 왕복이 줄어듦).
- /tmp 쓰기 차단 — 임시 파일은 `~/` 사용.

## 다음 세션 할 일 (우선순위)

### 0. (선택) v0.3.1 릴리스
CHANGELOG `Unreleased` 항목 승격 + `MapFormat.releaseVersion` "0.3.1" +
README 트랜스크립트 재실행 확인(로컬 빌드 복구 후) + `git tag v0.3.1`.
릴리스 체크리스트는 AGENTS.md에 있음.

### 1. CLT 재설치로 로컬 빌드 복구 (sudo — 사용자 조치 필요)
위 ⚠ 참조. 복구 전에는 로컬 `swift test` 불가.

### 2. 공개 후 유통 (기획서 "첫 공개 전략" — 해자 축 ②③)
- **데모 GIF**: 에이전트가 시뮬레이터에서 버그 발견 → `where_is`로 소스 즉시 오픈 →
  수정 → `affected_tests`로 관련 3개만 재실행 → 통과. 전체 UI 테스트 실행과의
  소요·토큰 대비를 같은 화면에.
- **커뮤니티 접근**: Arbigent·XcodeBuildMCP·AccessibilitySnapshot 쪽에
  `match_snapshot` interop 어댑터 소개. HN/Reddit(iosProgramming)은 GIF 확보 후.
- Homebrew tap·SPM 원라인 설치는 수요 신호 확인 후.

### 3. 검증 저변 확대 (해자 축 ①)
- 오픈소스 iOS 앱 2~4개 저장소 추가 크롤(firefox-ios/Wikipedia급 UIKit 대형 앱
  포함 권장) → README "실전 검증" 표에 정밀도·재현율·크롤 시기 추가. 대형 앱
  크롤 전에 이번 인덱싱 수정이 이미 들어와 있음(성능 여유 확보).
- 새 패턴 발견 시 먼저 실패하는 테스트 → ConstantTable/Visitor 확장.

### 4. 이후 (v1.x 후보)
- 심볼 앵커 정밀화(extension/조건부 컴파일 → IndexStoreDB), 화면 경계 유추,
  identifier 코드젠, Android/Kotlin 확장.
- 위 "기록만 하고 미수정" 관찰 목록(타임아웃·라인 버퍼 상한·심볼릭 링크 가드).

## 함정·결정 기록 (다시 읽기)

- **release 빌드는 수 분** — swift-syntax. 백그라운드 실행 + 폴링 필수.
- **DemoApp에 직접 `git init` 금지** — `Scripts/setup-demo.sh`만. 데모 잔여 상태는
  커밋 전 정리: `rm -rf Examples/DemoApp/.git Examples/DemoApp/.locus` +
  `git checkout -- Examples/DemoApp`.
- **경로 기준계** — sourceRoot == repoRoot면 prefix `""`, 중첩이면 하위 경로,
  저장소 밖이어야 nil(접미사 폴백). 회귀 테스트 2종:
  `testNestedSourceRootAvoidsCrossModuleFalsePositives`,
  `testRepoRootSourceRootAvoidsCrossModuleFalsePositives`.
- **버전 단일 소스**: `MapFormat.releaseVersion`(현재 "0.3.0", Unreleased 있음).
- **orphan은 UI-쿼리 위치 한정** — 상수 참조도 동일 규칙(리터럴과 대칭).
- **idb는 선택 의존** — `--udid`는 선행 `-` 가드. env 경유 PATH 조회가 유일한
  경로(/usr/bin 표준 위치 없음 — GitDiff의 /usr/bin/git 우선과는 다른 이유).
- **셸 cwd 잔류 주의** — 항상 `cd /Users/jinhongan/Desktop/Z_Workspace/locus &&`부터.
- **GitHub**: `gh` 인증됨(계정 `ictechgy`). remote `origin` =
  https://github.com/ictechgy/locus. 푸시·릴리스는 승인 게이트 아님.

## 참조

- 기획서(차별화·이름 결정·첫 공개 전략): `기획서.md` · 에이전트 지침: `AGENTS.md` ·
  사용법·실전 검증 수치: `README.md` · 버전 이력: `CHANGELOG.md`
- 이번 검토 상세: PR #1 (https://github.com/ictechgy/locus/pull/1)
- 실전 검증 대상 클론: /tmp/breadcrumb-p0/element-x-ios (휘발성 — 필요시 재클론)
- 포트폴리오 맥락: 형제 프로젝트 `../coroner`(프로덕션 부검) — 부검 결과의 화면
  귀속에 locus가 쓰이는 접점은 기획서 차별화 표에 명시.
