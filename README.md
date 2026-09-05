# breadcrumb

> **에이전트에게 화면과 코드 사이의 지도를 줘라.**
> (Give your agent a map between the screen and the code.)

**breadcrumb**은 iOS 앱의 접근성 요소(accessibility element)와 Swift 소스 코드 사이의
정적 트레이스빌리티 맵을 만드는 CLI 도구이자 MCP 서버다. SwiftUI의
`.accessibilityIdentifier("...")` 수정자와 UIKit의
`button.accessibilityIdentifier = "..."` 대입을 크롤하고, UI 테스트 안의
식별자 문자열을 역색인해서, 양방향 질의에 답한다:

- **`where-is`** — "이 스위치는 어느 줄에서 태어났나?" → `SettingsView.swift:9`,
  앵커 `SettingsView.notificationsToggle`, 이 식별자를 쓰는 테스트 3개.
- **`what-renders`** — "이 뷰 파일/심볼은 무엇을 렌더하나?" → 요소 목록.
- **`affected-tests`** — "이 diff가 깨뜨릴 UI 테스트는?" → 전체 UI 테스트 대신
  영향받는 테스트만.
- **`missing-identifiers`** — "자동화 불가능한 컨트롤이 얼마나 있나?" → 팀의
  자동화 부채 계량기.
- **`mcp`** — 같은 4가지 질의를 Claude Code·Cursor 같은 에이전트에 툴로 제공.

결정적(deterministic)으로 동작하고, LLM을 쓰지 않으며, 완전 로컬에서 돈다.

---

## 설치

요구 사항: macOS 13+, Swift 5.9+ 도구체인 (Swift 6.x 포함).

```bash
git clone <this-repository>
cd breadcrumb
swift build -c release
# 바이너리: .build/release/breadcrumb
```

빠른 실행:

```bash
.build/release/breadcrumb --version
# breadcrumb 0.1.0
```

---

## Quickstart

`Examples/DemoApp`은 자체 git 저장소(초기 커밋 + 커밋되지 않은 변경 1개)를 가진
데모 앱 소스다. 그대로 따라할 수 있다.

```console
$ cd Examples/DemoApp

# 1. 크롤 — 정적 맵 + 테스트 역색인 (결과는 .breadcrumb/ 에 원자적 기록)
$ breadcrumb crawl .
  elements:              6
  identifiers in tests:  5
  orphan literals:       1
  missing identifiers:   2

# 2. 요소 → 소스 (+ 이 식별자를 쓰는 테스트)
$ breadcrumb where-is checkout.pay
{
  "elements" : [ { "file" : "Sources/CheckoutViewController.swift",
                   "line" : 13, "symbol" : "CheckoutViewController.viewDidLoad",
                   "kind" : "UIButton", "confidence" : "high", ... } ],
  "tests" : [ { "file" : "Tests/ProfileUITests.swift", "line" : 33 } ]
}

# 3. 심볼/파일 → 렌더하는 요소
$ breadcrumb what-renders CheckoutViewController
{ "elements" : [ "checkout.pay", "checkout.coupon" ] }

# 4. 변경 → 영향받는 테스트 (워킹 트리의 dirty change 기준)
$ breadcrumb affected-tests
{
  "changedFiles" : [ "Sources/ProfileView.swift" ],
  "tests" : [ { "file" : "Tests/ProfileUITests.swift", "identifier" : "profile.notifications" }, ... ]
}

# 5. 자동화 부채 — 식별자 없는 컨트롤
$ breadcrumb missing-identifiers
{ "total" : 2, "perFile" : [ { "file" : "Sources/ProfileView.swift",
    "findings" : [ { "kind" : "Button", "reason" : "swiftui-call", ... } ] }, ... ] }

# 6. MCP 서버 (stdio JSON-RPC 2.0) — 아래 "에이전트 연동" 참고
$ breadcrumb mcp
```

---

## CLI 레퍼런스

```
breadcrumb crawl <sourceRoot> [--tests-glob G]... [--exclude P]... [--out DIR]
breadcrumb where-is <identifier> [--out DIR]
breadcrumb what-renders <symbol|file> [--out DIR]
breadcrumb affected-tests [--ref <git-ref>] [--files f1,f2] [--out DIR]
breadcrumb missing-identifiers [--out DIR]
breadcrumb mcp [--out DIR]
```

| 명령 | 설명 |
|---|---|
| `crawl` | `sourceRoot` 아래 모든 `*.swift`를 SwiftSyntax로 파싱해 식별자·라벨을 추출하고, 테스트 경로(`--tests-glob`, 기본 `*Tests*`)의 문자열 리터럴을 역색인한다. `.breadcrumb/` 아래 `elements.json`, `tests.json`, `orphans.json`, `missing-identifiers.json`, `index.json`을 기록한다. 같은 입력이면 항상 같은 바이트(결정적), 임시 파일 + rename 원자적 덮어쓰기. |
| `where-is` | 식별자를 가진 모든 요소(파일:줄:칼럼, 심볼 앵커, 종류, 라벨)와 그 식별자를 참조하는 테스트 목록. |
| `what-renders` | 타겟을 심볼(`ProfileView`, `ProfileView.avatarToggle`) 또는 파일 경로로 해석해 그 안에 앵커된 요소들을 반환. |
| `affected-tests` | 변경 파일(기본: 워킹 트리 `git diff HEAD`, `--ref` 지정 시 `git diff <ref>`) → 그 파일에 앵커된 요소 → 중복 제거된 테스트 목록. `--files`로 git 없이 직접 지정도 가능. |
| `missing-identifiers` | 상호작용 가능해 보이는데 식별자가 없는 컨트롤(SwiftUI 호출부, UIKit 프로퍼티)을 파일별로 나열. |
| `mcp` | stdio 위 JSON-RPC 2.0 MCP 서버. `initialize` / `tools/list` / `tools/call` 지원, EOF에서 정상 종료. |

지도 위치는 기본 `./.breadcrumb`이고 `--out`으로 바꾼다. 질의는 같은 작업
디렉터리에서(또는 `--out`으로) 실행한다.

---

## 에이전트 연동 (MCP)

Claude Code (`claude_desktop_config.json` / `.mcp.json`):

```json
{
  "mcpServers": {
    "breadcrumb": {
      "command": "/absolute/path/to/breadcrumb",
      "args": ["mcp"],
      "cwd": "/path/to/your/ios/project"
    }
  }
}
```

Cursor (`~/.cursor/mcp.json`): 동일한 형식.

제공 툴: `where_is(identifier)`, `what_renders(target)`,
`affected_tests(ref?, files?)`, `missing_identifiers()`.
프로토콜 버전 `2024-11-05`, 알 수 없는 메서드는 JSON-RPC `-32601` 에러.

---

## 맵의 생김새

```json
{
  "identifier": "profile.notifications",
  "label": "Allow notifications",
  "kind": "Toggle",
  "file": "Sources/ProfileView.swift",
  "line": 13,
  "column": 17,
  "symbol": "ProfileView.body",
  "confidence": "high"
}
```

---

## 정직한 한계 (v0.1)

- **심볼 앵커는 구문 기반** — `symbol`은 SwiftSyntax 트리의 바깥 타입 + 바깥
  프로퍼티/함수 선언에서 유추한 것(`Type.member`)이다. IndexStoreDB 기반
  심볼 해석은 로드맵 항목이며, 익스텐션으로 나뉜 선언·조건부 컴파일 블록
  너머의 정밀도는 보장하지 않는다.
- **동적 시뮬레이터 스냅샷은 범위 밖** — 정적 원장만으로
  `where_is`/`what_renders`가 성립한다 (v0.3 계획).
- **정적 분석의 누락이 있다** — 보간된/동적 식별자 문자열
  (`.accessibilityIdentifier(someVariable)`)은 추출하지 못하고, 라벨-식별자
  결합은 같은 문장/체인 안에서만 이루어진다. 누락은 잔차
  (`missing-identifiers`, 동적 리터럴 스킵)로 드러낸다 — 버그가 아니라 기능.
- **칼럼은 UTF-8 바이트 기준**, 다바이트 문자가 앞에 오면 편집기 칼럼과 어긋날
  수 있다.
- **`affected-tests` 미추적 파일 제외** — untracked 파일은 git diff에 안
  나오므로 반영되지 않는다. 명시적 `--files`로 보완 가능.
- **역색인 리터럴 매칭은 정확 일치** — 테스트의 오탈자 식별자는 `orphans.json`
  에 잔차로 잡힌다(존재하지 않는 식별자 모양 문자열). 발견이 곧 가치.

## 차별화·경계

| 인접 | breadcrumb과의 차이 |
|---|---|
| Arbigent / mobile-mcp / Agent Device | UI 드라이브 자동화. 코드 연결 없음 — 경쟁이 아니라 상위 계층 소비자(드라이브하다 발견한 요소를 `where_is`로). |
| FixAlly (학술 시제품) | identifier→source 탐색을 a11y 자동수정에 한정. 유지되는 도구가 아니며 역참조·테스트 역색인·에이전트 인터페이스 없음. 정직하게 선행 연구로 인용. |
| XcodeSelectiveTesting | 타깃/모듈 단위 선택 실행. breadcrumb은 심볼→UI 요소→테스트 단위. |
| Serena / SourceKit-LSP | 소스 심볼 네비게이션. UI 요소·접근성 트리 개념이 없음. |
| AccessibilitySnapshot (Cash App) | 접근성 계층 스냅샷 회귀 테스트. 소스 매핑·임팩트 질의 없음. |

## 로드맵

```
v0.1  정적 크롤러(SwiftSyntax) + where_is / what_renders          ← 현재
v0.2  테스트 역색인 + affected_tests(diff)                        ← 현재 (v0.2 범위 포함 선행 출시)
v0.3  동적 스냅샷 결합(시뮬레이터 a11y 덤프 매칭) + MCP 4툴 고도화
v1.x  화면 경계 유추, IndexStoreDB 심볼 앵커, identifier 코드젠,
      Android 확장(Kotlin/Compose)
```

---

## English (short)

**breadcrumb** builds a static traceability map between iOS accessibility
elements and Swift source, and answers both directions: *which source line
created this UI element* (`where-is`) and *which UI tests does this diff
affect* (`affected-tests`). It uses SwiftSyntax (no LLM, fully local),
writes a deterministic map under `.breadcrumb/`, reverse-indexes identifier
literals in your UI tests, reports interactive controls without identifiers,
and exposes the same queries over a hand-rolled stdio MCP server (JSON-RPC
2.0) for Claude Code / Cursor. Symbol anchors are syntax-context based
(`Type.member`); IndexStoreDB resolution is future work. See the Korean
sections above for the full CLI reference and honest limitations.

## License

MIT — see [LICENSE](LICENSE).
