# HANDOFF — 다음 세션 인수인계

## 2026-09-08 전체 코드 검토 — 다음 수정 작업

- 기준: `main@e967fb4`, 검토 시작 시 워킹트리 clean. 이번에는 이 문서만 갱신했으며 아래 항목은 **미수정**이다.
- 범위: CLI·SwiftSyntax crawler/constants·역색인, source 순회·map 저장/로드·query, git·snapshot/idb·MCP, 테스트·설정·스크립트·문서. 아래 실측이 과거 CLT 장애/CI만 검증 가능 설명보다 우선한다.

### 재현으로 확인한 수정 필요 사항

1. **P1 · correctness — 일부 맵 파일이 없어도 정상 조회로 처리한다.** `Sources/LocusCore/MapStore.swift:69`, `Sources/LocusCore/Engine.swift:16`.
   - 필수 데이터 파일 누락을 빈 배열로 바꾼다. 완전한 합성 맵에서 affected tests=1이던 결과가 `tests.json` 하나를 없애자 exit 0/tests=0으로 바뀌어 필요한 테스트를 놓친다.
   - 다음 수정: 필수 파일·index/version/count를 검증하고 부분 맵이면 재크롤 안내 오류를 낸다. 잘못된 JSON 자체는 현재도 decode 오류를 전파하므로 그 오류가 삼켜진다고 설명하지 않는다. 여러 파일의 세대 일관성과 `MapStore.swift:60`의 교체 오류 무시도 함께 정리한다. 파일별 누락 및 교체 실패 회귀를 추가한다.
2. **P1 · correctness — 맵 위치와 git/명시 파일의 경로 기준계가 다르다.** `Sources/LocusCore/Engine.swift:16`, `Sources/LocusCore/Engine.swift:86`, `Sources/LocusCLI/main.swift:273`.
   - absolute `--out`으로 맵을 읽어도 git은 launcher CWD에서 실행한다. 합성 repo 밖 `/tmp`에서 호출하자 `Not a git repository`, exit 2가 됐다. 명시 `files` 분기는 repoRoot를 구하지 않아 `Other/Sources/Foo.swift`가 `App/Sources/Foo.swift` 요소에 잘못 매칭됐다.
   - 다음 수정: map.sourceRoot에서 실제 repo 기준을 구해 git과 명시 파일을 같은 방식으로 정규화한다. repo 밖 launcher, nested sourceRoot의 sibling 파일, 명시적 `files=[]`가 git fallback을 일으키지 않는 경우를 테스트한다.
3. **P2 · correctness — 변경 가능한 var를 확정 상수로 기록한다.** `Sources/LocusCore/ConstantTable.swift:125`.
   - literal initializer를 가진 var도 상수표에 들어간다. 합성 `static var mutable = "default.id"`가 high-confidence identifier로 추출됐다. 런타임 재할당 시 맵이 틀린다.
   - 다음 수정: immutable 선언만 상수/namespace alias로 인정하거나 mutable 값은 미해석으로 남긴다. static/instance var의 부정 사례와 immutable let namespace chain을 함께 테스트한다.
4. **P2 · correctness — 빈 identifier와 해석 실패 UIKit 할당이 missing 목록에서도 빠진다.** `Sources/LocusCore/Crawler.swift:54`, `Sources/LocusCore/Crawler.swift:159`, `Sources/LocusCore/Crawler.swift:298`.
   - 빈 문자열 identifier가 element에서는 빠지지만 identifier 보유 그룹으로는 인정되고, UIKit은 값 해석 전 assigned로 기록한다. 합성 빈 ID Button·unresolved UIKit 할당이 모두 `missing=[]`로 나왔다.
   - 다음 수정: 해석된 nonempty identifier만 보유로 인정하고 UIKit도 해석 후 그룹/대상별로 판단한다. empty literal과 computed/member-chain 미해석 회귀를 추가한다.
5. **P2 · reliability — 값 없는 CLI 옵션을 문자열 true로 받아 산출물을 쓴다.** `Sources/LocusCLI/main.swift:68`.
   - `crawl Sources --out`이 오류 대신 exit 0으로 `./true/` 맵 디렉터리를 생성했다. parser가 값 없는 모든 옵션을 flag처럼 처리한다.
   - 다음 수정: 명령별 값 옵션/flag/반복 옵션을 구분하고 누락·unknown·잘못된 추가 인자를 오류 처리한다. `--out/--ref/--files/--udid`의 값 누락과 빈 `--name=`를 CLI 회귀 테스트로 고정한다.
6. **P2 · reliability — 디렉터리 symlink 하나로 crawl 전체가 실패한다.** `Sources/LocusCore/Glob.swift:84`.
   - symlink와 디렉터리를 구분하지 않고 재귀한다. 합성 외부 디렉터리 링크 및 ancestor loop 모두 현재 환경에서 Cocoa 256/POSIX 20, exit 2였다. 무한 순환을 재현한 것은 아니다.
   - 다음 수정: 링크는 기본 skip하거나, 명시적으로 추적할 경우 실제 경로 포함 여부와 방문한 파일 ID를 검사한다. 정상 파일/디렉터리 링크·루프의 처리 계약을 테스트한다.

### 기존 미해결 항목 — 정적 확인, 추가 검증 필요

7. **P3 · reliability/performance — MCP frame 크기 상한이 없다.** `Sources/LocusCore/MCPEngine.swift:228`.
   - newline 전 buffer가 계속 커지고 앞부분 삭제도 반복한다. 크기 상한 부재는 코드에서 확인했으나 대형 입력 메모리·반복 복사 비용은 측정하지 않았다.
   - 다음 수정: 실제 snapshot 크기를 고려한 최대 frame과 초과 입력 처리를 정하고, 경계/초과/여러 frame 테스트 및 메모리 측정을 한다.
8. **P3 · reliability — git/idb 프로세스에 timeout이 없다.** `Sources/LocusCore/GitDiff.swift:56`, `Sources/LocusCore/Snapshot.swift:80`.
   - 기존 관찰이 계속 유효하며 실제 idb 정지를 이번에 재현한 것은 아니다. timeout·종료 정리·CLI/MCP 오류 전달을 정의한 뒤 sleeping fake executable로 검증한다. 기존 stdout/stderr 동시 drain은 유지한다.

### 실행 검증과 제약

- `swift test --skip-update --disable-automatic-resolution --scratch-path /tmp/z-workspace-review-20260908/locus/swift-build`: **53 tests, 0 failures**. Swift 6.4/Xcode 27 beta.
- 원본 `.build/checkouts`는 비어 있었고 pinned swift-syntax 600.0.1을 기존 전역 bare cache에서 scratch로 materialize했다. 로그는 `Fetching ... from cache`/`Fetched ... from cache (0.08s)`이며 원격 update는 없었다. 원본 manifest/lock은 수정하지 않았다.
- Foundation-only 실제 소스의 직접 swiftc harness와 scratch-built 실제 CLI로 위 재현을 실행했다. 증거: `/tmp/z-workspace-review-20260908/locus/`의 `swift-test.log`, `partial-map-repro.log`, `out-cwd-repro.log`, `pure-core-repros.log`, `crawler-edge-repro.log`, `cli-missing-value-repro.log`, `symlink-*-repro.log`.
- 실 idb·외부 앱 crawl·release build·setup-demo는 미실행. 일반 후속 검증은 저장소 루트의 `swift test`; 캐시를 이용할 때는 위 offline 명령을 재사용한다.
- 오래된 “Xcode 없음/CLT 파손/CI만 가능/tmp 쓰기 불가” 설명은 현재 로컬 빌드·테스트·임시 재현 성공으로 대체한다. AGENTS/README의 50 tests도 현재 53과 다르다.

### 다음 세션 시작

`AGENTS.md`와 이 절을 읽고 부분 맵 로드와 경로 기준계 오류부터 회귀 테스트로 고정·수정한다. 이후 identifier 정밀도·CLI/symlink 처리를 해결한다. 기존 v0.3.1 릴리스와 실전 검증 확대는 검증이 끝난 뒤 진행한다.

---

## 이전 세션 기록 — 작성 당시 상태

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
