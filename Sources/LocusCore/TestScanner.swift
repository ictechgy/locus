import Foundation
import SwiftSyntax
import SwiftParser

/// Reverse index: scans test/automation sources for string literals that match
/// known element identifiers, and tracks orphan literals — identifier-shaped
/// strings in UI-query positions (`app.buttons["id"]`, identifier/matching
/// call arguments) that match no known element (typos, removed elements,
/// debt).
///
/// Constant references resolve too: tests written against a constant table
/// (`app.buttons[A11yIdentifiers.roomScreen.name]`) index exactly like string
/// literals, using the table built during the crawl.
public struct TestScanner {
    public init() {}

    /// - Parameters:
    ///   - root: source root the relative file paths are based on.
    ///   - globs: glob patterns deciding which files are "test/automation" files
    ///     (default `*Tests*`).
    ///   - identifiers: known element identifiers from the crawl.
    ///   - constants: the constant table built during the crawl (resolves
    ///     `A11yIdentifiers.…` references in tests).
    public func scan(
        root: URL,
        globs: [String],
        excludes: [String],
        knownIdentifiers: Set<String>,
        constants: ConstantTable = ConstantTable()
    ) throws -> (tests: [ElementTests], orphans: [OrphanLiteral]) {
        let files = try SourceTree.swiftFiles(under: root, excludes: excludes)
            .filter { Glob.matchesAny(path: $0, patterns: globs) }
        let readRoot = root.resolvingSymlinksInPath()
        var usages: [String: [TestReference]] = [:]
        var orphans: [OrphanLiteral] = []

        for relative in files {
            let source = SourceTree.readSource(at: readRoot.appendingPathComponent(relative))
            let tree = Parser.parse(source: source)
            let visitor = LiteralVisitor(constants: constants, source: source)
            visitor.walk(tree)
            for found in visitor.found {
                guard let value = found.value else { continue } // dynamic literals: skip
                if knownIdentifiers.contains(value) {
                    usages[value, default: []].append(
                        TestReference(file: relative, line: found.line, column: found.column)
                    )
                } else if found.isQueryContext, Self.isIdentifierShaped(value) {
                    orphans.append(OrphanLiteral(
                        literal: value, file: relative, line: found.line, column: found.column
                    ))
                }
            }
        }

        let tests = usages
            .map { ElementTests(identifier: $0.key, tests: $0.value.sorted { ($0.file, $0.line, $0.column) < ($1.file, $1.line, $1.column) }) }
            .sorted { $0.identifier < $1.identifier }
        let sortedOrphans = orphans.sorted { ($0.file, $0.line, $0.column, $0.literal) < ($1.file, $1.line, $1.column, $1.literal) }
        return (tests, sortedOrphans)
    }

    /// Heuristic for "this string literal looks like an accessibility identifier":
    /// - dotted with at least two segments (`settings.notifications`), or
    /// - lowercase snake_case of 5+ characters (`login_button`).
    /// Only applied to query-position strings: shape alone proved too broad on
    /// a real codebase (file names, bundle IDs and domains all look dotted).
    public static func isIdentifierShaped(_ value: String) -> Bool {
        guard !value.isEmpty, value.count >= 5, value.count <= 128 else { return false }
        guard value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }) else { return false }
        if value.contains(".") {
            let segments = value.split(separator: ".", omittingEmptySubsequences: true)
            return segments.count >= 2
        }
        if value.contains("_") {
            let first = value.first!
            return first.isLowercase || first.isNumber
        }
        return false
    }
}

/// Collects string literals and resolvable constant references from a test
/// syntax tree, remembering whether each literal sits in a UI-query position.
private final class LiteralVisitor: SyntaxVisitor {
    struct Found {
        var value: String?
        var line: Int
        var column: Int
        /// True for `app.buttons["…"]` subscripts and identifier/matching call
        /// arguments — the positions where a literal is being *used as* an
        /// element identifier. Orphan reporting is restricted to these;
        /// arbitrary dotted strings elsewhere proved to be 95% noise (P0).
        var isQueryContext: Bool
    }

    var found: [Found] = []
    private let constants: ConstantTable
    private let lineIndex: LineIndex

    init(constants: ConstantTable, source: String) {
        self.constants = constants
        self.lineIndex = LineIndex(source)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        var text = ""
        var isPlain = true
        for segment in node.segments {
            switch segment {
            case .stringSegment(let segment):
                text += segment.content.text
            default:
                isPlain = false
            }
        }
        let position = lineIndex.lineColumn(
            utf8Offset: node.positionAfterSkippingLeadingTrivia.utf8Offset
        )
        found.append(Found(
            value: isPlain ? text : nil,
            line: position.line,
            column: position.column,
            isQueryContext: Self.isQueryPosition(node)
        ))
        return .skipChildren
    }

    /// Constant references: `A11yIdentifiers.roomScreen.name` anywhere in the
    /// test resolves through the crawl's constant table.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let rootName = SyntaxText.normalizedName(node.baseName.text)
        guard constants.rootTypeNames.contains(rootName) else { return .visitChildren }
        var components = [rootName]
        var current = node.parent
        while let member = current?.as(MemberAccessExprSyntax.self) {
            components.append(SyntaxText.normalizedName(member.declName.baseName.text))
            current = member.parent
        }
        guard let value = constants.resolve(chain: components) else { return .visitChildren }
        let position = lineIndex.lineColumn(
            utf8Offset: node.positionAfterSkippingLeadingTrivia.utf8Offset
        )
        found.append(Found(value: value, line: position.line, column: position.column, isQueryContext: true))
        return .visitChildren
    }

    /// `app.buttons["id"]`, `app.buttons[A11y.id]` → the literal/argument sits
    /// in a subscript call. `matching("id")`-style identifier queries count too.
    static func isQueryPosition(_ node: SyntaxProtocol) -> Bool {
        guard let argument = node.parent?.as(LabeledExprSyntax.self),
              let list = argument.parent else { return false }
        // The argument's parent is the labeled-expr *list*; the call is above it.
        guard let container = list.parent else { return false }
        if container.is(SubscriptCallExprSyntax.self) { return true }
        if let call = container.as(FunctionCallExprSyntax.self),
           let name = SyntaxText.simpleCallName(call.calledExpression) {
            return ["accessibilityIdentifier", "identifier", "matching", "element", "descendantsMatching"].contains(name)
        }
        return false
    }
}
