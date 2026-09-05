import XCTest
@testable import BreadcrumbCore

/// MCP server: initialize/tools-list/tools-call handshake driven in-process by
/// feeding lines to MCPEngine — no socket, no process spawn.
final class MCPTests: XCTestCase {
    private var engine: MCPEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let source = """
        import SwiftUI

        struct Screen: View {
            var body: some View {
                Button("Sign in") {}
                    .accessibilityIdentifier("settings.signIn")
                Slider(value: .constant(0.5))
            }
        }
        """
        let root = Fixture.makeTree("mcp", files: [
            "Sources/Screen.swift": source,
            "Tests/ScreenUITests.swift": "import XCTest\nfinal class T: XCTestCase { func testA() { let id = \"settings.signIn\"; _ = id } }\n",
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)
        engine = MCPEngine(engine: Engine(map: map, workingDirectory: root))
    }

    private func json(_ line: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(line?.data(using: .utf8), "expected a response line")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInitializeHandshake() throws {
        let response = try json(engine.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(response["id"] as? Int, 1)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "breadcrumb")
        XCTAssertEqual(serverInfo["version"] as? String, "0.1.0")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
    }

    func testInitializedNotificationIsSilent() {
        XCTAssertNil(engine.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testToolsListHasFourTools() throws {
        _ = engine.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        let response = try json(engine.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertEqual(
            Set(tools.compactMap { $0["name"] as? String }),
            ["where_is", "what_renders", "affected_tests", "missing_identifiers"]
        )
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object", "every tool declares an object input schema")
        }
    }

    func testToolsCallWhereIs() throws {
        let request = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"where_is","arguments":{"identifier":"settings.signIn"}}}"#
        let response = try json(engine.handle(line: request))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("settings.signIn"), "tool payload must name the identifier")
        XCTAssertTrue(text.contains("Screen.body"), "tool payload must carry the symbol anchor")
    }

    func testToolsCallMissingIdentifiersFindsTheSlider() throws {
        let request = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"missing_identifiers","arguments":{}}}"#
        let response = try json(engine.handle(line: request))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("Slider"), "the unidentified Slider must surface via MCP")
    }

    func testToolsCallErrorIsReportedNotThrown() throws {
        let request = #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"where_is","arguments":{"identifier":"nope.missing"}}}"#
        let response = try json(engine.handle(line: request))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertTrue(try XCTUnwrap(content.first?["text"] as? String).contains("nope.missing"))
    }

    func testUnknownMethodIsJSONRPCError() throws {
        let response = try json(engine.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#))
        XCTAssertNil(response["result"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testParseError() throws {
        let response = try json(engine.handle(line: "not json at all"))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
        XCTAssertNil(response["id"] as? Int)
    }

    func testUnknownTool() throws {
        let response = try json(engine.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"drive_simulator"}}"#))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }
}
