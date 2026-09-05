import Foundation
import SwiftSyntax
import SwiftParser

/// Reverse index: scans test/automation sources for string literals that match
/// known element identifiers, and tracks orphan literals — identifier-shaped
/// strings that match no known element (typos, removed elements, debt).
public struct TestScanner {
    public init() {}

    /// - Parameters:
    ///   - root: source root the relative file paths are based on.
    ///   - globs: glob patterns deciding which files are "test/automation" files
    ///     (default `*Tests*`).
    ///   - identifiers: known element identifiers from the crawl.
    public func scan(
        root: URL,
        globs: [String],
        excludes: [String],
        knownIdentifiers: Set<String>
    ) throws -> (tests: [ElementTests], orphans: [OrphanLiteral]) {
        let files = try SourceTree.swiftFiles(under: root, excludes: excludes)
            .filter { Glob.matchesAny(path: $0, patterns: globs) }
        let readRoot = root.resolvingSymlinksInPath()
        var usages: [String: [TestReference]] = [:]
        var orphans: [OrphanLiteral] = []

        for relative in files {
            let source = SourceTree.readSource(at: readRoot.appendingPathComponent(relative))
            let tree = Parser.parse(source: source)
            let lineIndex = LineIndex(source)
            let visitor = StringLiteralVisitor()
            visitor.walk(tree)
            for literal in visitor.literals {
                guard let value = literal.value else { continue } // dynamic literals: skip
                if knownIdentifiers.contains(value) {
                    let position = lineIndex.lineColumn(utf8Offset: literal.utf8Offset)
                    usages[value, default: []].append(
                        TestReference(file: relative, line: position.line, column: position.column)
                    )
                } else if Self.isIdentifierShaped(value) {
                    let position = lineIndex.lineColumn(utf8Offset: literal.utf8Offset)
                    orphans.append(OrphanLiteral(
                        literal: value, file: relative,
                        line: position.line, column: position.column
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
    /// Documented in the README as intentionally broad — orphans are leads, not
    /// verdicts.
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

/// Collects plain string literals from a syntax tree.
private final class StringLiteralVisitor: SyntaxVisitor {
    struct Found {
        var value: String?
        var utf8Offset: Int
    }
    var literals: [Found] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Skip interpolated literals for matching purposes but still keep them
        // out entirely (value == nil) so orphans don't false-positive.
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
        literals.append(Found(value: isPlain ? text : nil, utf8Offset: node.positionAfterSkippingLeadingTrivia.utf8Offset))
        return .skipChildren
    }
}
