# locus

> **에이전트에게 화면과 코드 사이의 지도를 줘라.**
> (Give your agent a map between the screen and the code.)
>
> *locus — where every UI element lives in source.*

**locus**는 iOS 앱의 접근성 요소(accessibility element)와 Swift 소스 코드 사이의
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
- **`snapshot`** — "지금 화면의 이 요소는 어느 줄?" → 런타임 접근성 트리 덤프를
  정적 맵과 매칭(identifier 직매칭 high, 라벨 휴리스틱 medium/low, 잔차 리포트).
- **`mcp`** — 같은 5가지 질의를 Claude Code·Cursor 같은 에이전트에 툴로 제공.

결정적(deterministic)으로 동작하고, LLM을 쓰지 않으며, 완전 로컬에서 돈다.

---

## 설치

요구 사항: macOS 13+, Swift 5.9+ 도구체인 (Swift 6.x 포함).

```bash
git clone https://github.com/ictechgy/locus
cd locus
swift build -c release
# 바이너리: .build/release/locus
```

빠른 실행:

```bash
.build/release/locus --version
# locus 0.1.0
```

---

## Quickstart

`Examples/DemoApp`은 SwiftUI + UIKit + UI 테스트 소스를 담은 데모 앱이다.
4번(git 기반 affected-tests)을 그대로 따라하려면 먼저 `Scripts/setup-demo.sh`로
데모용 임시 git 환경을 만들고(초기 커밋 + 커밋되지 않은 변경 1개), git 없이
시도하려면 `affected-tests --files Sources/ProfileView.swift`로 대체한다.

```console
$ cd Examples/DemoApp
$ ../../Scripts/setup-demo.sh   # git 기반 데모용 (선택)

# 1. 크롤 — 정적 맵 + 테스트 역색인 (결과는 .locus/ 에 원자적 기록)
$ locus crawl .
  elements:              6
  identifiers in tests:  5
  orphan literals:       1
  missing identifiers:   2

# 2. 요소 → 소스 (+ 이 식별자를 쓰는 테스트)
$ locus where-is checkout.pay
{
  "elements" : [ { "file" : "Sources/CheckoutViewController.swift",
                   "line" : 13, "symbol" : "CheckoutViewController.viewDidLoad",
                   "kind" : "UIButton", "confidence" : "high", ... } ],
  "tests" : [ { "file" : "Tests/ProfileUITests.swift", "line" : 33 } ]
}

# 3. 심볼/파일 → 렌더하는 요소
$ locus what-renders CheckoutViewController
{ "elements" : [ "checkout.pay", "checkout.coupon" ] }

# 4. 변경 → 영향받는 테스트 (워킹 트리의 dirty change 기준)
$ locus affected-tests
{
  "changedFiles" : [ "Sources/ProfileView.swift" ],
  "tests" : [ { "file" : "Tests/ProfileUITests.swift", "identifier" : "profile.notifications" }, ... ]
}

# 5. 자동화 부채 — 식별자 없는 컨트롤
$ locus missing-identifiers
{ "total" : 2, "perFile" : [ { "file" : "Sources/ProfileView.swift",
    "findings" : [ { "kind" : "Button", "reason" : "swiftui-call", ... } ] }, ... ] }

# 6. 동적 스냅샷 — 런타임 화면 요소 ↔ 소스 매칭
#    (덤프는 idb ui describe-all, XCUITest 헬퍼 등 어느 도구에서든; stdin도 가능)
$ locus snapshot dump.json
{ "coverage" : 0.667, "matches" : [ { "identifier" : "checkout.pay",
    "matchedBy" : "identifier", "confidence" : "high",
    "elements" : [ { "file" : "Sources/CheckoutViewController.swift", "line" : 13, ... } ] },
    ... ], "unidentifiedOnScreen" : [ ... ] }

# 7. MCP 서버 (stdio JSON-RPC 2.0) — 아래 "에이전트 연동" 참고
$ locus mcp
```

---

## CLI 레퍼런스

```
locus crawl <sourceRoot> [--tests-glob G]... [--exclude P]... [--out DIR]
locus where-is <identifier> [--out DIR]
locus what-renders <symbol|file> [--out DIR]
locus affected-tests [--ref <git-ref>] [--files f1,f2] [--out DIR]
locus missing-identifiers [--out DIR]
locus snapshot <dump.json|-> [--udid <udid>] [--out DIR]
locus mcp [--out DIR]
```

| 명령 | 설명 |
|---|---|
| `crawl` | `sourceRoot` 아래 모든 `*.swift`를 SwiftSyntax로 파싱해 식별자·라벨을 추출하고, 테스트 경로(`--tests-glob`, 기본 `*Tests*`)의 문자열 리터럴과 상수 참조를 역색인한다. `.locus/` 아래 `elements.json`, `tests.json`, `orphans.json`, `missing-identifiers.json`, `index.json`을 기록한다. 같은 입력이면 항상 같은 바이트(결정적), 임시 파일 + rename 원자적 덮어쓰기. |
| `where-is` | 식별자를 가진 모든 요소(파일:줄:칼럼, 심볼 앵커, 종류, 라벨)와 그 식별자를 참조하는 테스트 목록. |
| `what-renders` | 타겟을 심볼(`ProfileView`, `ProfileView.avatarToggle`) 또는 파일 경로로 해석해 그 안에 앵커된 요소들을 반환. |
| `affected-tests` | 변경 파일(기본: 워킹 트리 `git diff HEAD`, `--ref` 지정 시 `git diff <ref>`) → 그 파일에 앵커된 요소 → 중복 제거된 테스트 목록. `--files`로 git 없이 직접 지정도 가능. |
| `missing-identifiers` | 식별자 없는 **인터랙티브** 컨트롤(버튼·토글·입력필드 등 — 탭/타이핑 대상)을 파일별로 나열. 정적 텍스트·이미지는 라벨로 매칭 가능하므로 제외. |
| `snapshot` | 런타임 접근성 트리 덤프(JSON)를 정적 맵과 매칭. identifier 직매칭(`high`), 고유 라벨 휴리스틱(`medium`, kind 불일치 시 `low`). 잔차 리포트: 화면상 식별자 없는 요소(자동화 부채), 맵에 없는 식별자(동적 식별자·스테일 맵 단서), 화면에 안 보이는 맵 식별자, 커버리지 점수. `--udid` 시 `idb ui describe-all`로 덤프를 직접 캡처(prototype, idb는 선택 의존). |
| `mcp` | stdio 위 JSON-RPC 2.0 MCP 서버. `initialize` / `tools/list` / `tools/call` 지원, EOF에서 정상 종료. |

지도 위치는 기본 `./.locus`이고 `--out`으로 바꾼다. 질의는 같은 작업
디렉터리에서(또는 `--out`으로) 실행한다.

---

## 에이전트 연동 (MCP)

Claude Code (`claude_desktop_config.json` / `.mcp.json`) — 쿼리가 지도를 찾을
위치를 고정하기 위해 CWD 대신 `--out`으로 프로젝트의 `.locus`를 지정하는
것이 이식 가능한 방법:

```json
{
  "mcpServers": {
    "locus": {
      "command": "/absolute/path/to/locus",
      "args": ["mcp", "--out", "/path/to/your/ios/project/.locus"]
    }
  }
}
```

클라이언트가 `cwd`를 지원하면 `args: ["mcp"]` + `cwd: /path/to/your/ios/project`로
같은 효과를 낼 수 있다.

Cursor (`~/.cursor/mcp.json`): 동일한 형식.

제공 툴: `where_is(identifier)`, `what_renders(target)`,
`affected_tests(ref?, files?)`, `missing_identifiers()`,
`match_snapshot(dump)` — 에이전트가 자기 도구(idb·XCUITest·XcodeBuildMCP)로
뽑은 접근성 트리 덤프를 넘기면 매칭된 소스와 잔차를 돌려준다.
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

## 정직한 한계 (v0.3)

- **심볼 앵커는 구문 기반** — `symbol`은 SwiftSyntax 트리의 바깥 타입 + 바깥
  프로퍼티/함수 선언에서 유추한 것(`Type.member`)이다. IndexStoreDB 기반
  심볼 해석은 로드맵 항목이며, 익스텐션으로 나뉜 선언·조건부 컴파일 블록
  너머의 정밀도는 보장하지 않는다.
- **동적 식별자는 추출하지 않는다** — 보간된 문자열, 함수형 상수
  (`A11y.numpad(3)`), 계산 속성·`switch`로 런타임에 결정되는 식별자
  (element-x-ios의 `session_verification-*` 사례)는 정적 원장에 없다.
  테스트가 이를 참조하면 `orphans`로, 화면에 나타나면 `snapshot`의
  `unmatchedIdentifiers`로 드러난다 — 버그가 아니라 자동화 부채의 계량.
- **상수 해석의 경계** — `enum`/`struct` 멤버의 문자열 리터럴과 String raw-value
  enum 케이스, `static let ns = Type()` 네임스페이스 별칭을 해석한다.
  같은 (타입, 멤버) 이름의 충돌 선언은 그 항목을 버린다(모호하면 미해석).
  타입 이름은 중첩 경로 없이 키로 쓰므로, 서로 다른 타입이 같은 이름+멤버를
  가지면 해석을 생략한다.
- **정적 분석의 누락이 있다** — 라벨-식별자 결합은 같은 문장/체인 안에서만
  이루어진다. 누락은 잔차로 드러난다.
- **UIKit missing 판정은 같은 파일 안에서만 연결된다** — 아웃릿 프로퍼티 선언과
  `accessibilityIdentifier` 대입이 다른 파일(extension 등)에 나뉘어 있으면
  missing-identifiers에 과다 보고될 수 있다.
- **칼럼은 UTF-8 바이트 기준**, 다바이트 문자가 앞에 오면 편집기 칼럼과 어긋날
  수 있다.
- **`affected-tests` 미추적 파일 제외** — untracked 파일은 git diff에 안
  나오므로 반영되지 않는다. 명시적 `--files`로 보완 가능.
- **역색인 리터럴 매칭은 정확 일치** — 테스트의 오탈자 식별자는 `orphans.json`
  에 잔차로 잡힌다(존재하지 않는 식별자 모양 문자열). orphan 판정은
  UI-쿼리 위치(서브스크립트·식별자/매칭 호출 인자)로 제한한다 — 형태만으로는
  파일명·번들ID·도메인과 구분되지 않는다(실전 코드베이스에서 노이즈 95%).
- **`snapshot` 매칭의 한계** — 라벨 휴리스틱은 고유 라벨에만 적용(중복 라벨은
  매칭하지 않는다), kind 불일치 시 `low`. 커버리지는 매칭 노드 비율이지
  검증 커버리지가 아니다. `--udid` 캡처는 idb 설치가 필요하며 idb 출력
  형식의 변경을 따라갈 수 있다(필드 별칭으로 흡수).
- **데모의 내부 git은 선택** — DemoApp 소스는 이 저장소에 일반 파일로
  포함되어 있다. `Scripts/setup-demo.sh`가 임시 내부 git을 만들며, 그때부터
  부모 저장소의 `git status`에 `m Examples/DemoApp`이 보인다(데모 설계상
  의도). 없애려면 `Examples/DemoApp/.git`을 삭제하면 된다.

## 실전 검증 (P0, 2026-09)

[element-x-ios](https://github.com/element-hq/element-x-ios)(프로덕션 SwiftUI 앱,
Swift 파일 1,385개)로 검증했다:

- 크롤 4.6초(릴리스 빌드) — 병렬화 불필요.
- 식별자 콜사이트 158곳 중 146개 추출(92%). 잔차 12곳은 함수형 상수·
  계산 속성 등 **정적으로 불가능한 형태**가 전부 — 표본 검수상 오추출 0건.
- 이 저장소의 식별자 159곳 중 리터럴은 1곳뿐 — 상수 해석 없이는 이 앱에서
  요소가 0개 추출된다. 상수 중심 문화가 베스트 프랙티스인 팀일수록
  이 기능이 결정적이다.
- orphan 노이즈 243 → 6(잔여 6 중 4건은 진짜 동적-식별자 부채).
- missing-identifiers 1,349 → 424(비인터랙티브 종류 제외).

## 차별화·경계

| 인접 | locus와의 차이 |
|---|---|
| Arbigent / mobile-mcp / Agent Device | UI 드라이브 자동화. 코드 연결 없음 — 경쟁이 아니라 상위 계층 소비자(드라이브하다 발견한 요소를 `where_is`로). |
| FixAlly (학술 시제품) | identifier→source 탐색을 a11y 자동수정에 한정. 유지되는 도구가 아니며 역참조·테스트 역색인·에이전트 인터페이스 없음. 정직하게 선행 연구로 인용. |
| XcodeSelectiveTesting | 타깃/모듈 단위 선택 실행. locus는 심볼→UI 요소→테스트 단위. |
| Serena / SourceKit-LSP | 소스 심볼 네비게이션. UI 요소·접근성 트리 개념이 없음. |
| AccessibilitySnapshot (Cash App) | 접근성 계층 스냅샷 회귀 테스트. 소스 매핑·임팩트 질의 없음. |

## 로드맵

```
v0.1  정적 크롤러(SwiftSyntax) + where_is / what_renders
v0.2  테스트 역색인 + affected_tests(diff) + 상수 해석·실전 검증(P0)
v0.3  동적 스냅샷 결합(접근성 트리 덤프 매칭, 잔차 리포트) + MCP 5툴   ← 현재
v1.x  화면 경계 유추, IndexStoreDB 심볼 앵커, identifier 코드젠,
      Android 확장(Kotlin/Compose)
```

---

## 개발

```bash
make test        # swift test — 50 tests
make release     # 첫 릴리스 빌드는 swift-syntax 컴파일로 수 분 걸린다
```

- 의존성은 `swift-syntax` 하나뿐이다. 다른 의존성을 추가할 때는 기획서의
  "완전 로컬·결정적" 원칙과 함께 논의할 것.
- `Examples/DemoApp`에 직접 `.git`을 만들지 말 것 — `Scripts/setup-demo.sh`를
  쓸 것 (이유는 "정직한 한계" 참고).

---

## English (short)

**locus** builds a static traceability map between iOS accessibility
elements and Swift source, and answers both directions: *which source line
created this UI element* (`where-is`), *which UI tests does this diff
affect* (`affected-tests`), and — matching a runtime accessibility-tree dump
against the map — *which source line created the element on screen right
now* (`snapshot`). Identifiers centralized in constants (`enum
A11yIdentifiers` namespaces, raw-value enums) resolve like inline literals.
It uses SwiftSyntax (no LLM, fully local), writes a deterministic map under
`.locus/`, reverse-indexes identifier literals and constant references
in your UI tests, reports interactive controls without identifiers, and
exposes the same queries over a hand-rolled stdio MCP server (JSON-RPC
2.0) for Claude Code / Cursor. Validated on a 1,385-file production app
(4.6 s crawl, 100% sampled precision). Symbol anchors are syntax-context
based (`Type.member`); IndexStoreDB resolution is future work. See the
Korean sections above for the full CLI reference and honest limitations.

## License

MIT — see [LICENSE](LICENSE).
