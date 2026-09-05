# AGENTS.md — breadcrumb

이 저장소에서 작업하는 AI 코딩 에이전트용 지침. 사람 기여자는 [README.md](README.md)와
[기획서.md](기획서.md)를 먼저 읽을 것. 충돌하면 기획서 > README > 이 파일 순.

## 이 저장소는 (30초 요약)

iOS 접근성 요소 ↔ Swift 소스 코드의 정적 트레이스빌리티 맵. SwiftSyntax로
`accessibilityIdentifier`/`accessibilityLabel`(리터럴·상수·레이블드 인자)을
크롤하고, UI 테스트의 식별자 참조를 역색인해 양방향 질의(CLI + MCP 5툴)에
답한다. 런타임 접근성 트리 덤프를 맵과 매칭하는 동적 스냅샷(`snapshot`)도
있다. **LLM 불요, 완전 로컬, 맵 출력은 바이트 단위 결정적**이 계약이다.

## 명령 (반드시 저장소 루트에서)

```bash
swift build            # 증분 빌드, 수 초 (의존성 swift-syntax는 이미 checkout됨)
swift test             # 50개 XCTest, 수 초. 커밋 전 필수
swift build -c release # 주의: 첫 릴리스 빌드는 swift-syntax 컴파일로 수 분.
                       # 반드시 run_in_background로 돌리고 짧게 폴링할 것 —
                       # 긴 블로킹 호출은 세션 타임아웃을 유발한다
make test / make release
```

주의: 셸 작업 디렉터리가 다른 저장소로 남아 있으면 `swift test`가 엉뚱한 패키지를
돌린다. 항상 `cd /path/to/breadcrumb &&`를 붙이는 습관.

## 구조 지도

```
Sources/BreadcrumbCore/       라이브러리 타깃 — 모든 로직은 여기에
  Models.swift                도메인 타입(ElementRecord·MissingIdentifier·BreadcrumbMap)
                              + MapFormat(버전 단일 소스: releaseVersion)
  Crawler.swift               SwiftSyntax 비지터 — SwiftUI 수정자·레이블드 인자 호출 +
                              UIKit 대입 추출, RawHit 병합, 심볼 앵커, kind 추정,
                              인터랙티브 컨트롤만 missing 대상
  ConstantTable.swift         정적 상수 해석 — enum/struct 멤버 리터럴, String raw-value
                              enum(암시 케이스명 포함), 네임스페이스 별칭
                              (static let ns = Type()), 백틱 멤버 정규화. 실전 앱의
                              식별자 대부분이 상수 형태임(P0 실측)
  TestScanner.swift           역색인 — 테스트의 문자열 리터럴 + 상수 참조 ↔ 식별자
                              정확 일치, orphan은 UI-쿼리 위치로 제한(형태만으론
                              파일명·번들ID와 구분 불가 — 실측 노이즈 95%)
  Snapshot.swift              동적 스냅샷 — 덤프 파싱(필드 별칭), idb 캡처(선택 의존),
                              매처(identifier high / 고유 라벨 medium·low, 잔차·커버리지)
  Engine.swift                질의 엔진(whereIs·whatRenders·affectedTests·
                              missingIdentifiers·matchSnapshot)
                              + repoRelativePrefix(경로 기준계 정렬 — 아래 불변식 5)
  GitDiff.swift               git 읽기 전용 연동 — 파이프 동시 drain 필수(교착 방지),
                              /usr/bin/git 우선(GUI 앱 PATH 문제), option-like ref 거부
  Glob.swift                  최소 글롭(* ? **). SourceTree — 숨김/빌드 디렉터리 제외 순회
  MapStore.swift              .breadcrumb/ 5개 JSON — 원자적 쓰기(temp+rename), 결정적 바이트
  MCPEngine.swift             손작성 stdio JSON-RPC 2.0 + 5툴. MCPStdio.run = 루프
Sources/BreadcrumbCLI/main.swift  CLI 엔트리(top-level). 로직 추가 금지, 코어로
Tests/BreadcrumbCoreTests/    XCTest. FixtureSupport가 temp 트리·git 드라이버 제공
Examples/DemoApp/             README 트랜스크립트의 입력 (부모 저장소에 일반 파일로 추적)
Scripts/setup-demo.sh         데모용 임시 내부 git 생성 — DemoApp에 직접 git init 금지
```

## 불변식 (깨뜨리면 제품 정체성이 무너진다)

1. **코어에 LLM·네트워크 호출 금지.** 크롤 결과는 같은 입력이면 같은 바이트
   (타임스탬프·비결정 정렬 금지 — MapStore 결정성 테스트가 지킨다).
2. **의존성은 swift-syntax 하나.** ArgumentParser조차 안 쓴다 — 파서 추가는
   hand-rolled(`main.swift`의 `parse`) 패턴 따르기.
3. **경로 기준계를 섞지 말 것.** `element.file`은 sourceRoot 상대, git 변경 파일은
   저장소 루트 상대. 비교는 반드시 `Engine.repoRelativePrefix`로 정렬 후 — suffix
   추정만 쓰면 형제 모듈 오검출로 회귀(이 버그의 회귀 테스트가
   `testNestedSourceRootAvoidsCrossModuleFalsePositives`다).
4. **맵 파일은 원자적으로.** `MapStore.writeAtomic` 우회 금지. 읽는 쪽은 언제든
   크롤 중간 상태를 볼 수 있다고 가정.
5. **MCP 응답은 한 줄 JSON.** 멀티라인 텍스트는 `content[].text` 내부로. 툴 실패는
   `isError: true`.
6. **git은 읽기 전용.** `GitDiff`는 diff·rev-parse만 — 상태 변경 명령 금지.
7. **`Examples/DemoApp`에 `.git`을 만들지 말 것** — `Scripts/setup-demo.sh`만이
   정식 경로. 부모 저장소의 gitlink 회귀를 막는다(히스토리: commit 243da0a).
8. **`.breadcrumb/`는 런타임 산출물.** 커밋 금지(gitignore됨).

## 테스트 관습

- `FixtureSupport` 사용: `Fixture.makeTree`(temp 소스 트리), `Fixture.crawl`,
  `Fixture.git/gitIdentity`(temp git 저장소 — 실제 git 이진으로 통합 테스트).
- 파서 추출 정밀도는 file:line:column·symbol까지 정확히 단언한다.
- 프로세스 스폰이 필요한 것(MCP stdio)은 in-process `handle(line:)` 테스트가
  기본, 스폰 테스트는 보조.
- 새 동작 = 실패하는 테스트 먼저.

## 자주 하는 실수

- 심볼 앵커를 IndexStoreDB처럼 다루는 것 — 구문 컨텍스트 유추다. README
  "정직한 한계"가 정확한 경계다. 새 한계는 거기에 기록.
- 릴리스 빌드를 포그라운드로 돌리고 기다리다 죽는 것 — 위 "명령" 경고 재독.
- 버전 문자열은 `MapFormat.releaseVersion` 단일 소스 — main.swift·MCPEngine·
  tool 문자열 모두 여기서 파생된다. 다른 곳에 하드코딩 금지.

## 릴리스 체크리스트

1. `swift test` 그린 (로컬)
2. `CHANGELOG.md` 항목 추가
3. `MapFormat.releaseVersion` 갱신 — CLI `--version`, MCP `serverInfo`, 맵의
   `tool` 문자열이 전부 따라온다
4. README 트랜스크립트가 실제 실행 결과와 일치하는지 재실행으로 확인
5. 태그: `git tag v0.x.y`
