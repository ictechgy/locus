import Foundation

/// Model Context Protocol server over stdio, hand-rolled on JSON-RPC 2.0
/// (no MCP SDK dependency). Implemented methods: `initialize`, `tools/list`,
/// `tools/call`, `ping`. Notifications are acknowledged with silence; unknown
/// requests get `-32601`; malformed JSON gets `-32700`; EOF exits cleanly.
///
/// The request/response core is `handle(line:)`, which is pure enough to drive
/// from tests without spawning a process.
public final class MCPEngine {
    private let engine: Engine
    private let protocolVersion = "2024-11-05"

    public init(engine: Engine) {
        self.engine = engine
    }

    /// Handle one stdin line. Returns the JSON-RPC response line, or nil when
    /// the input was a notification or blank.
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let request = json as? [String: Any] else {
            return render(id: NSNull(), error: rpcError(-32700, "Parse error: invalid JSON"))
        }
        let id = request["id"] ?? NSNull()
        guard let method = request["method"] as? String else {
            return render(id: id, error: rpcError(-32600, "Invalid Request: missing method"))
        }
        let isNotification = (request["id"] == nil) || (request["id"] is NSNull)

        if method.hasPrefix("notifications/") {
            return nil // notifications are never answered
        }
        guard !isNotification else {
            // A request without an id is a notification by definition; we do
            // not run it and do not answer.
            return nil
        }

        switch method {
        case "initialize":
            return render(id: id, result: initializeResult())
        case "ping":
            return render(id: id, result: [:])
        case "tools/list":
            return render(id: id, result: ["tools": toolDescriptors()])
        case "tools/call":
            return handleToolsCall(id: id, params: request["params"] as? [String: Any])
        default:
            return render(id: id, error: rpcError(-32601, "Method not found: \(method)"))
        }
    }

    // MARK: - Tool dispatch

    private func handleToolsCall(id: Any, params: [String: Any]?) -> String {
        guard let params, let name = params["name"] as? String else {
            return render(id: id, error: rpcError(-32602, "Invalid params: tools/call requires params.name"))
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let payload: Encodable
            switch name {
            case "where_is":
                payload = try engine.whereIs(try stringArgument(arguments, "identifier", tool: name))
            case "what_renders":
                payload = try engine.whatRenders(try stringArgument(arguments, "target", tool: name))
            case "affected_tests":
                let ref = optionalStringArgument(arguments, "ref")
                let files = (arguments["files"] as? [Any])?.compactMap { $0 as? String }
                    ?? optionalStringArgument(arguments, "files")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                payload = try engine.affectedTests(ref: ref, files: files)
            case "missing_identifiers":
                payload = engine.missingIdentifiers()
            case "match_snapshot":
                let dump = try stringArgument(arguments, "dump", tool: name)
                payload = try engine.matchSnapshot(dump: dump)
            default:
                return render(id: id, error: rpcError(-32602, "Unknown tool: \(name)"))
            }
            return render(id: id, result: [
                "content": [["type": "text", "text": payload.locusJSON()]],
                "isError": false,
            ])
        } catch let error as LocusError {
            return render(id: id, result: [
                "content": [["type": "text", "text": "{\"error\": \(jsonQuoted(error.message))}"]],
                "isError": true,
            ])
        } catch {
            return render(id: id, result: [
                "content": [["type": "text", "text": "{\"error\": \"internal error\"}"]],
                "isError": true,
            ])
        }
    }

    private func stringArgument(_ arguments: [String: Any], _ key: String, tool: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw LocusError("Invalid params: \(tool) requires a string argument '\(key)'")
        }
        return value
    }

    private func optionalStringArgument(_ arguments: [String: Any], _ key: String) -> String? {
        (arguments[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Tool descriptors

    struct ToolDescriptor {
        var name: String
        var description: String
        var schema: [String: Any]
    }

    public var toolNames: [String] { ["where_is", "what_renders", "affected_tests", "missing_identifiers", "match_snapshot"] }

    func toolDescriptors() -> [[String: Any]] {
        [
            ToolDescriptor(
                name: "where_is",
                description: "Find where a UI element with the given accessibility identifier is defined in source (file:line, symbol anchor) and which tests reference it.",
                schema: objectSchema(required: ["identifier"], properties: [
                    "identifier": ["type": "string", "description": "accessibility identifier, e.g. settings.notifications"],
                ])
            ),
            ToolDescriptor(
                name: "what_renders",
                description: "List UI elements rendered by a symbol (Type, Type.member) or a source file, per the crawled map.",
                schema: objectSchema(required: ["target"], properties: [
                    "target": ["type": "string", "description": "symbol anchor like SettingsView.body or a file path"],
                ])
            ),
            ToolDescriptor(
                name: "affected_tests",
                description: "Given changed files (git diff, optionally against a ref, or explicit file list), return the deduplicated UI tests that touch elements in those files.",
                schema: objectSchema(required: [], properties: [
                    "ref": ["type": "string", "description": "git ref to diff against; omit for working-tree changes"],
                    "files": {
                        var list: [String: Any] = ["type": "array", "items": ["type": "string"]]
                        list["description"] = "explicit changed file paths; overrides git diff"
                        return list
                    }(),
                ])
            ),
            ToolDescriptor(
                name: "missing_identifiers",
                description: "Interactive-looking controls with no accessibilityIdentifier, grouped per file — the team's automation debt.",
                schema: objectSchema(required: [], properties: [:])
            ),
            ToolDescriptor(
                name: "match_snapshot",
                description: "Match a runtime accessibility-tree dump (JSON array of elements, from idb ui describe-all, XCUITest, or similar) against the static map: identifier direct-match (high), label heuristic (medium/low), plus residual report (unidentified on-screen nodes, unknown identifiers).",
                schema: objectSchema(required: ["dump"], properties: [
                    "dump": ["type": "string", "description": "the accessibility-tree dump as JSON text (array of element objects, or an object with an `elements` array)"],
                ])
            ),
        ].map { descriptor in
            [
                "name": descriptor.name,
                "description": descriptor.description,
                "inputSchema": descriptor.schema,
            ]
        }
    }

    private func objectSchema(required: [String], properties: [String: Any]) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    // MARK: - Response rendering

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "locus", "version": MapFormat.releaseVersion],
        ]
    }

    private func rpcError(_ code: Int, _ message: String) -> [String: Any] {
        ["code": code, "message": message]
    }

    private func render(id: Any, result: [String: Any]) -> String {
        sortedJSON(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func render(id: Any, error: [String: Any]) -> String {
        sortedJSON(["jsonrpc": "2.0", "id": id, "error": error])
    }

    /// JSON-RPC responses are single lines; keys sorted for deterministic tests.
    private func sortedJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"internal error\"}}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonQuoted(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String],
              let quoted = array.first else {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return quoted
    }
}

/// Reassembles newline-delimited frames from stdin chunks with a hard size
/// cap: a real accessibility-tree dump reaches a few megabytes, anything
/// past the cap is a stuck or hostile sender, not a request.
public struct FrameAssembler {
    public enum Outcome: Equatable {
        /// Complete frames (newline included), in order.
        case frames([String])
        /// The pending frame exceeded the cap; the buffer was reset and the
        /// caller should answer with a JSON-RPC error and keep serving.
        case overflow
    }

    public private(set) var buffer = Data()
    public let maximumBytes: Int

    public init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    /// Append one received chunk; extracts every complete frame with a
    /// single front-removal per chunk (removing the prefix per line is
    /// O(n²) on large chunks). Newlines (0x0A) never occur inside UTF-8
    /// multibyte sequences, so byte-wise splitting is safe.
    public mutating func append(_ chunk: Data) -> Outcome {
        buffer.append(chunk)
        var frames: [String] = []
        var consumed = buffer.startIndex
        while let newline = buffer[consumed...].firstIndex(of: 0x0A) {
            if let line = String(data: buffer.subdata(in: consumed..<newline), encoding: .utf8) {
                frames.append(line)
            }
            consumed = buffer.index(after: newline)
        }
        buffer.removeSubrange(buffer.startIndex..<consumed)
        if buffer.count > maximumBytes {
            buffer.removeAll(keepingCapacity: false)
            return .overflow
        }
        return .frames(frames)
    }

    /// Flush a trailing frame that ended without a newline (EOF).
    public mutating func flushTrailing() -> String? {
        guard !buffer.isEmpty else { return nil }
        let line = String(data: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: false)
        return line.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// The stdio loop: read chunks until EOF, answer per frame, then exit 0.
public enum MCPStdio {
    /// Real dumps (idb describe-all of a busy screen) reach a few MB;
    /// 32 MiB bounds a frame generously while keeping memory finite.
    public static let maximumFrameBytes = 32 * 1024 * 1024

    public static func run(engine: MCPEngine) -> Int32 {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        var assembler = FrameAssembler(maximumBytes: maximumFrameBytes)
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break } // EOF — clean exit
            switch assembler.append(chunk) {
            case .frames(let frames):
                for frame in frames {
                    if let response = engine.handle(line: frame) {
                        stdout.write(Data((response + "\n").utf8))
                    }
                }
            case .overflow:
                stdout.write(Data((
                    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"request exceeds \(maximumFrameBytes) bytes\"}}\n"
                ).utf8))
            }
        }
        // Flush any trailing frame without a newline.
        if let line = assembler.flushTrailing(), let response = engine.handle(line: line) {
            stdout.write(Data((response + "\n").utf8))
        }
        stdout.write(Data())
        return 0
    }
}
