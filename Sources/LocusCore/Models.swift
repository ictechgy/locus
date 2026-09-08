import Foundation

/// The static traceability record for one UI element that carries an
/// accessibility identifier or label.
public struct ElementRecord: Codable, Equatable {
    /// The runtime accessibility identifier, e.g. `settings.notifications`.
    public var identifier: String
    /// The accessibility label if one was found in the same statement/chain, if any.
    public var label: String?
    /// Best-effort element kind guessed from call-site / property type context.
    public var kind: String
    /// Source file path relative to the crawled source root, POSIX style.
    public var file: String
    /// 1-based line of the identifier assignment.
    public var line: Int
    /// 1-based UTF-8 column of the identifier assignment.
    public var column: Int
    /// Syntax-context based anchor, e.g. `SettingsView.notificationsToggle`.
    /// See README: this is derived from the enclosing type + enclosing
    /// property/func in the syntax tree, not from IndexStoreDB (future work).
    public var symbol: String
    /// Static direct match on an explicit identifier literal is always "high".
    public var confidence: String

    public init(
        identifier: String, label: String? = nil, kind: String,
        file: String, line: Int, column: Int, symbol: String, confidence: String = "high"
    ) {
        self.identifier = identifier
        self.label = label
        self.kind = kind
        self.file = file
        self.line = line
        self.column = column
        self.symbol = symbol
        self.confidence = confidence
    }
}

/// A UI element that looks interactive but carries no accessibility identifier.
public struct MissingIdentifier: Codable, Equatable {
    public var kind: String
    public var file: String
    public var line: Int
    public var column: Int
    public var symbol: String
    /// "swiftui-call" (a control call site without an identifier modifier)
    /// or "uikit-property" (a UIKit control property never assigned one).
    public var reason: String
    public var hasLabel: Bool

    public init(
        kind: String, file: String, line: Int, column: Int,
        symbol: String, reason: String, hasLabel: Bool
    ) {
        self.kind = kind
        self.file = file
        self.line = line
        self.column = column
        self.symbol = symbol
        self.reason = reason
        self.hasLabel = hasLabel
    }
}

/// One literal usage of an identifier inside a test/automation file.
public struct TestReference: Codable, Equatable {
    public var file: String
    public var line: Int
    public var column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// Per-element reverse index entry: identifier -> where tests reference it.
public struct ElementTests: Codable, Equatable {
    public var identifier: String
    public var tests: [TestReference]

    public init(identifier: String, tests: [TestReference]) {
        self.identifier = identifier
        self.tests = tests
    }
}

/// An identifier-shaped string literal found in test code that matches no known
/// element. Usually a typo, a removed element, or an identifier that never
/// existed — automation debt, surfaced on purpose.
public struct OrphanLiteral: Codable, Equatable {
    public var literal: String
    public var file: String
    public var line: Int
    public var column: Int

    public init(literal: String, file: String, line: Int, column: Int) {
        self.literal = literal
        self.file = file
        self.line = line
        self.column = column
    }
}

/// Top-level map document: deterministic, no timestamps.
public struct LocusMap: Codable, Equatable {
    public var version: Int
    public var tool: String
    public var sourceRoot: String
    public var elements: [ElementRecord]
    public var tests: [ElementTests]
    public var orphans: [OrphanLiteral]
    public var missingIdentifiers: [MissingIdentifier]

    public init(
        version: Int = MapFormat.version,
        tool: String = MapFormat.tool,
        sourceRoot: String,
        elements: [ElementRecord],
        tests: [ElementTests],
        orphans: [OrphanLiteral],
        missingIdentifiers: [MissingIdentifier]
    ) {
        self.version = version
        self.tool = tool
        self.sourceRoot = sourceRoot
        self.elements = elements
        self.tests = tests
        self.orphans = orphans
        self.missingIdentifiers = missingIdentifiers
    }
}

public enum MapFormat {
    public static let version = 1
    /// Single source of truth for the release version (CLI, MCP serverInfo, tool string).
    public static let releaseVersion = "0.3.1"
    public static let tool = "locus \(releaseVersion)"
    /// Default map directory, relative to the current working directory.
    public static let defaultDirectoryName = ".locus"
    /// Output formatting shared by every locus JSON surface (map files, CLI,
    /// MCP tool payloads) so the deterministic-bytes invariant cannot drift
    /// between writers.
    public static let jsonFormatting: JSONEncoder.OutputFormatting = [
        .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
    ]
}

/// An error surfaced to CLI/MCP consumers as a human-readable message.
public struct LocusError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
