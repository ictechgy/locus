# Changelog

## Unreleased

### Fixed

- `affected-tests`: crawling from the repository root itself (the common
  `locus crawl .` case) fell back to suffix path matching, so a change to a
  same-named file in a sibling directory was reported as affecting the
  crawled module's elements. Aligned frames (sourceRoot inside or equal to
  the repo root) now match exactly; suffix matching remains only when the
  sourceRoot lies outside the repository.
- Orphan gating for constant references (`app.buttons[A11y.x]`) now applies
  the same query-position rule as string literals — a constant bound with
  `let label = A11y.x` outside any UI query is no longer reported as orphan
  debt.
- `snapshot --udid`: values starting with `-` are rejected (same
  option-injection guard as git refs); `--help` USAGE now lists the
  `snapshot` command.

### Changed

- `match_snapshot` and `affected_tests` build identifier/label indexes once
  per query instead of linear scans per node/element
  (O(nodes × elements) → O(nodes + elements)); output is byte-identical.

## 0.3.0 — 2026-09-05

Dynamic snapshot matching: "the element on screen right now" → source.

### Changed

- Renamed **breadcrumb → locus** before first release (2026-09-06 decision):
  search-uniqueness beats narrative fit. Package, module (`LocusCore`),
  binary, MCP serverInfo, and the map directory (`.breadcrumb/` → `.locus/`)
  all renamed. This is the last rename window — the name is final.

### Added

- `snapshot <dump.json|-> [--udid UDID]`: match a runtime accessibility-tree
  dump against the static map. Identifier direct-match (`high`), unique-label
  heuristic (`medium`, `low` on kind disagreement), and the residual report —
  on-screen nodes without identifiers (automation debt), identifiers the
  ledger does not know (dynamic identifiers, stale maps), unseen ledger
  identifiers, and a coverage score.
- `match_snapshot` MCP tool: agents hand locus a dump from their own
  tooling (idb `ui describe-all`, XCUITest, XcodeBuildMCP) and get matched
  sources back — the interop path for UI-drive agents.
- Dump parsing tolerates common field vocabularies (`identifier`/`AXIdentifier`/
  `AXUniqueId`, `label`/`AXLabel`, `kind`/`type`/`role`) and both bare-array
  and `{"elements": […]}` envelopes.
- Read-only `idb ui describe-all --udid` capture (prototype dump source; idb
  is optional — file/stdin dumps always work).

## 0.2.0 — 2026-09-05

Real-codebase extraction. Validated on element-x-ios (1,385 Swift files):
crawl in 4.6 s (release build), 146 elements extracted at 100% sampled
precision, orphan noise down 97% (243 → 6), missing-identifier findings
down 69% (1,349 → 424, interactive controls only).

### Added

- Constant-table resolution: identifiers centralized in constants
  (`enum A11yIdentifiers` + namespace structs, raw-value string enums with
  implicit case-name values, backticked members) now extract like inline
  literals — pure SwiftSyntax, no index store. On the validation codebase
  158 of 159 identifier call sites use this pattern, not literals.
- Labeled-argument extraction: `accessibilityIdentifier:` / `accessibilityLabel:`
  call arguments (custom component parameters) extract like modifiers.
- Test-side constant references (`app.buttons[A11yIdentifiers.room.name]`)
  index exactly like string literals.

### Changed

- Orphan literals now require a UI-query position (subscripts like
  `app.buttons["…"]`, identifier/matching call arguments). Shape-alone
  matching reported file names, bundle IDs and domains as orphans — 95%
  noise on the validation codebase.
- `missing-identifiers` reports interactive controls only (Button, Toggle,
  fields, sliders, …). Static Text/Image/Label stay matchable by label and
  are not automation debt.

### Fixed

- `affected-tests --ref` rejects option-like refs and passes `--end-of-options`
  (git argument injection, e.g. `--output=`).
- git runs via `/usr/bin/git` when present — MCP clients launched from GUI
  apps pass a minimal PATH where `env git` lookup can fail.
- `--help` no longer hardcodes the version string (single source:
  `MapFormat.releaseVersion`).

## 0.1.0 — 2026-09-05

Initial release. A map between UI elements and source for agents.

### Added

- `crawl <sourceRoot>`: SwiftSyntax-based static crawler for SwiftUI
  `.accessibilityIdentifier` / `.accessibilityLabel` modifier calls and UIKit
  identifier/label assignments, with syntax-context symbol anchors
  (`Type.member`), kind guesses, and missing-identifier detection. Deterministic,
  atomically written map under `.locus/`.
- Reverse index of identifier string literals under test paths
  (`--tests-glob`, default `*Tests*`) with orphan-literal tracking.
- CLI queries: `where-is`, `what-renders`, `affected-tests`
  (`--ref` git diff or `--files`), `missing-identifiers`.
- `mcp`: stdio MCP server (JSON-RPC 2.0, no SDK) exposing `where_is`,
  `what_renders`, `affected_tests`, `missing_identifiers`; protocol
  `2024-11-05`; clean exit on EOF; JSON-RPC errors for unknown methods.
- `Examples/DemoApp`: SwiftUI + UIKit + UI-test fixtures in their own git
  repository for the `affected-tests` demo.
- 29 XCTests covering extraction accuracy, reverse index, missing-identifiers,
  git-driven affected-tests, and the MCP handshake (in-process).
- CI (GitHub Actions, macos-14): `swift build` + `swift test` +
  `swift build -c release`.
