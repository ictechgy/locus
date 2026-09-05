import XCTest
@testable import BreadcrumbCore

/// Dynamic snapshot matching (v0.3): identifier direct-match, label
/// heuristic with confidence, and the residual report — where the residual
/// IS the feature (on-screen automation debt, unknown identifiers).
final class SnapshotTests: XCTestCase {
    private let source = """
    import SwiftUI

    struct SettingsScreen: View {
        var body: some View {
            Toggle("Allow notifications", isOn: .constant(true))
                .accessibilityIdentifier("settings.notifications")
                .accessibilityLabel("Allow notifications")
            Button("Sign in") {}
                .accessibilityIdentifier("settings.signIn")
            Button("Help") {}
                .accessibilityIdentifier("settings.help")
                .accessibilityLabel("Get help")
        }
    }

    struct OtherScreen: View {
        var body: some View {
            Button("Pay") {}
                .accessibilityIdentifier("checkout.pay")
        }
    }
    """

    private func makeEngine() throws -> Engine {
        let root = Fixture.makeTree("snapshot", files: ["Sources/SettingsScreen.swift": source])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)
        return Engine(map: map, workingDirectory: root)
    }

    func testParseGenericAndIDBShapes() throws {
        let generic = #"[{"identifier": "a.b", "label": "A", "kind": "Button"}, {"identifier": "c.d"}]"#
        let genericNodes = try SnapshotDump.parse(generic)
        XCTAssertEqual(genericNodes.count, 2)
        XCTAssertEqual(genericNodes[0].identifier, "a.b")

        let idbStyle = #"[{"AXIdentifier": "x.y", "AXLabel": "X", "type": "Button"}, {"AXLabel": "No id", "type": "StaticText"}]"#
        let idbNodes = try SnapshotDump.parse(idbStyle)
        XCTAssertEqual(idbNodes[0].identifier, "x.y")
        XCTAssertEqual(idbNodes[0].kind, "Button")
        XCTAssertNil(idbNodes[1].identifier)

        let enveloped = #"{"elements": [{"identifier": "e.f"}]}"#
        XCTAssertEqual(try SnapshotDump.parse(enveloped).count, 1)
    }

    func testParseRejectsNonJSON() throws {
        XCTAssertThrowsError(try SnapshotDump.parse("not json"))
        XCTAssertThrowsError(try SnapshotDump.parse(#"{"nope": 1}"#))
    }

    func testIdentifierDirectMatchIsHigh() throws {
        let engine = try makeEngine()
        let report = try engine.matchSnapshot(dump: #"[{"identifier": "settings.signIn", "label": "Sign in", "kind": "Button"}]"#)
        let match = try XCTUnwrap(report.matches.first)
        XCTAssertEqual(match.matchedBy, "identifier")
        XCTAssertEqual(match.confidence, "high")
        XCTAssertEqual(match.elements.first?.symbol, "SettingsScreen.body")
        XCTAssertEqual(report.coverage, 1)
    }

    func testLabelHeuristicConfidence() throws {
        let engine = try makeEngine()
        // Unique label, kind agrees -> medium.
        let medium = try engine.matchSnapshot(dump: #"[{"label": "Get help", "kind": "Button"}]"#)
        XCTAssertEqual(medium.matches.first?.matchedBy, "label")
        XCTAssertEqual(medium.matches.first?.confidence, "medium")

        // Unique label but kind disagrees -> low.
        let low = try engine.matchSnapshot(dump: #"[{"label": "Get help", "kind": "StaticText"}]"#)
        XCTAssertEqual(low.matches.first?.confidence, "low")

        // No identifier on screen: still reported as automation debt.
        XCTAssertEqual(medium.unidentifiedOnScreen.count, 1)
    }

    func testAmbiguousLabelDoesNotMatch() throws {
        // Two elements share the label "Allow notifications" (the Toggle's
        // explicit label and its inferred one) — actually the fixture has one;
        // craft an ambiguous case directly.
        let matcher = SnapshotMatcher()
        let elements = [
            ElementRecord(identifier: "a.one", label: "Same", kind: "Button", file: "A.swift", line: 1, column: 1, symbol: "A.body"),
            ElementRecord(identifier: "a.two", label: "Same", kind: "Button", file: "B.swift", line: 1, column: 1, symbol: "B.body"),
        ]
        let report = matcher.match(nodes: [SnapshotNode(identifier: nil, label: "Same", kind: "Button", index: 0)], elements: elements)
        XCTAssertEqual(report.matches.first?.matchedBy, "none", "two candidates must not pick a winner")
        XCTAssertEqual(report.unidentifiedOnScreen.count, 1)
    }

    func testResidualsAndCoverage() throws {
        let engine = try makeEngine()
        let dump = #"""
        [{"identifier": "settings.signIn"}, {"identifier": "ghost.element"}, {"label": "Unknown label", "kind": "Button"}]
        """#
        let report = try engine.matchSnapshot(dump: dump)

        XCTAssertEqual(report.nodes, 3)
        XCTAssertEqual(report.unmatchedIdentifiers, ["ghost.element"], "on-screen id missing from the ledger is a lead")
        XCTAssertEqual(report.coverage, 0.333, "1 of 3 nodes matched")
        XCTAssertTrue(report.unseenIdentifiers.contains("checkout.pay"), "off-screen ledger ids are listed")
        XCTAssertFalse(report.unseenIdentifiers.contains("settings.signIn"))
        XCTAssertEqual(report.unidentifiedOnScreen.count, 1, "the label-only node has no identifier")
    }

    func testMatcherIsDeterministic() throws {
        let engine = try makeEngine()
        let dump = #"[{"identifier": "settings.help"}, {"label": "Get help"}]"#
        let a = try engine.matchSnapshot(dump: dump)
        let b = try engine.matchSnapshot(dump: dump)
        XCTAssertEqual(a, b)
    }

    func testMCPMatchSnapshotTool() throws {
        let engine = try makeEngine()
        let mcp = MCPEngine(engine: engine)
        let request = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"match_snapshot","arguments":{"dump":"[{\"identifier\": \"settings.signIn\"}]"}}}"#
        let response = try XCTUnwrap(mcp.handle(line: request))
        XCTAssertTrue(response.contains("matchedBy"), response)
        XCTAssertTrue(response.contains("identifier"), response)
        XCTAssertTrue(response.contains("settings.signIn"))
        XCTAssertFalse(response.contains("\"error\""), "a successful tool call is not a JSON-RPC error")
    }
}
