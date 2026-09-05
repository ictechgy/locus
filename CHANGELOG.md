# Changelog

## 0.1.0 — 2026-09-05

Initial release. A map between UI elements and source for agents.

### Added

- `crawl <sourceRoot>`: SwiftSyntax-based static crawler for SwiftUI
  `.accessibilityIdentifier` / `.accessibilityLabel` modifier calls and UIKit
  identifier/label assignments, with syntax-context symbol anchors
  (`Type.member`), kind guesses, and missing-identifier detection. Deterministic,
  atomically written map under `.breadcrumb/`.
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
