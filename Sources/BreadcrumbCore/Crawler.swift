import Foundation
import SwiftSyntax
import SwiftParser

/// Kind names breadcrumb recognizes as "interactive-looking" controls.
public enum ControlKnowledge {
    /// SwiftUI controls (used for kind guessing and missing-identifier detection).
    public static let swiftUIControls: Set<String> = [
        "Button", "Toggle", "TextField", "SecureField", "Slider", "Picker",
        "Stepper", "Link", "Menu", "NavigationLink", "DatePicker", "ColorPicker",
        "Image", "Text", "Label", "ProgressView", "TabView", "List",
    ]
    /// UIKit control types (used for kind guessing and missing-identifier detection).
    public static let uiKitControls: Set<String> = [
        "UIButton", "UISwitch", "UITextField", "UITextView", "UILabel",
        "UISlider", "UIStepper", "UIPickerView", "UIDatePicker", "UISegmentedControl",
        "UISearchBar", "UIPageControl", "UIImageView",
    ]
}

/// One raw accessibility-related finding before label/identifier merging.
public struct RawHit {
    enum Flavor { case identifier, label }
    var flavor: Flavor
    /// Literal string value, when statically known. Nil for interpolated or
    /// dynamic strings — a documented static-analysis residual.
    var value: String?
    var file: String
    var line: Int
    var column: Int
    var symbol: String
    var kindGuess: String
    /// Groups hits that belong to the same element: one modifier chain /
    /// statement (SwiftUI), or the same outlet property inside the same member
    /// (UIKit).
    var groupKey: String
    var hasLiteral: Bool { value != nil }
}

/// A SwiftUI control call site seen during the walk, used afterwards to decide
/// which ones ended up without an identifier.
public struct ControlCallSite {
    public var kind: String
    public var file: String
    public var line: Int
    public var column: Int
    public var symbol: String
    public var groupKey: String
    public var hasIdentifierHit: Bool
    public var hasLabelHit: Bool
}

/// Static crawler over Swift sources using SwiftSyntax.
///
/// Extracts:
/// - SwiftUI: `.accessibilityIdentifier("id")` / `.accessibilityLabel("...")`
///   modifier calls,
/// - UIKit: `x.accessibilityIdentifier = "id"` / `x.accessibilityLabel = "..."`
///   assignments,
/// from every `*.swift` file under a source root.
///
/// The symbol anchor (`Type.member`) is **syntax-context based**: it is the
/// enclosing nominal type plus the nearest enclosing property or function
/// declaration. It is not IndexStoreDB symbol resolution — documented future
/// work (see README).
public struct Crawler {
    public init() {}

    /// Crawl one file. `relativePath` is the POSIX path relative to the source
    /// root and is what appears in output.
    public func crawlFile(source: String, relativePath: String) throws
        -> (hits: [RawHit], controlSites: [ControlCallSite], outletCandidates: [MissingIdentifier], assignedOutletNames: Set<String>)
    {
        let tree = Parser.parse(source: source)
        let visitor = AccessibilityVisitor(relativePath: relativePath, source: source)
        visitor.walk(tree)
        return (visitor.hits, visitor.controlSites, visitor.outletCandidates, visitor.assignedOutletNames)
    }

    /// Crawl a whole source root.
    /// - Parameters:
    ///   - root: directory to crawl.
    ///   - excludes: glob patterns of paths to skip.
    /// - Returns: element records and missing-identifier findings, both sorted
    ///   deterministically.
    public func crawl(root: URL, excludes: [String]) throws -> (elements: [ElementRecord], missing: [MissingIdentifier]) {
        let files = try SourceTree.swiftFiles(under: root, excludes: excludes)
        let readRoot = root.resolvingSymlinksInPath()
        var allHits: [RawHit] = []
        var allSites: [ControlCallSite] = []
        var outletCandidates: [MissingIdentifier] = []
        var assignedNamesPerFile: [String: Set<String>] = [:]
        for relative in files {
            let source = SourceTree.readSource(at: readRoot.appendingPathComponent(relative))
            let (hits, sites, outlets, assigned) = try crawlFile(source: source, relativePath: relative)
            allHits.append(contentsOf: hits)
            allSites.append(contentsOf: sites)
            outletCandidates.append(contentsOf: outlets)
            assignedNamesPerFile[relative] = assigned
        }
        let records = Self.merge(hits: allHits).sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            if $0.column != $1.column { return $0.column < $1.column }
            return $0.identifier < $1.identifier
        }

        // Missing identifiers, SwiftUI side: control call sites whose statement
        // group never received an identifier hit.
        let identifierGroups = Set(allHits.filter { $0.flavor == .identifier && $0.hasLiteral }.map(\.groupKey))
        let labeledGroups = Set(allHits.filter { $0.flavor == .label && $0.hasLiteral }.map(\.groupKey))
        var missing: [MissingIdentifier] = allSites.compactMap { site in
            guard !identifierGroups.contains(site.groupKey) else { return nil }
            return MissingIdentifier(
                kind: site.kind, file: site.file, line: site.line, column: site.column,
                symbol: site.symbol, reason: "swiftui-call",
                hasLabel: labeledGroups.contains(site.groupKey)
            )
        }
        // UIKit side: control-typed properties never assigned an identifier.
        missing.append(contentsOf: outletCandidates.filter { candidate in
            let outletName = candidate.symbol.split(separator: ".").last.map(String.init) ?? ""
            return !assignedNamesPerFile[candidate.file, default: []].contains(outletName)
        })
        let sortedMissing = missing.sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.symbol < $1.symbol
        }
        return (records, sortedMissing)
    }

    // MARK: - Merging

    /// Merge identifier + label hits that share a group key into element records.
    static func merge(hits: [RawHit]) -> [ElementRecord] {
        var groups: [String: [RawHit]] = [:]
        for hit in hits {
            groups[hit.groupKey, default: []].append(hit)
        }
        var records: [ElementRecord] = []
        for groupHits in groups.values {
            let identifierHits = groupHits.filter { $0.flavor == .identifier }
            let labelHits = groupHits.filter { $0.flavor == .label }
            for idHit in identifierHits {
                guard let identifier = idHit.value, !identifier.isEmpty else { continue }
                let label = labelHits.first { $0.hasLiteral }?.value
                let kind = (idHit.kindGuess == "Unknown")
                    ? (labelHits.first?.kindGuess ?? "Unknown")
                    : idHit.kindGuess
                records.append(ElementRecord(
                    identifier: identifier,
                    label: label,
                    kind: kind,
                    file: idHit.file,
                    line: idHit.line,
                    column: idHit.column,
                    symbol: idHit.symbol
                ))
            }
        }
        return records
    }
}

// MARK: - Syntax visitor

private final class AccessibilityVisitor: SyntaxVisitor {
    let relativePath: String
    var hits: [RawHit] = []
    var controlSites: [ControlCallSite] = []
    var outletCandidates: [MissingIdentifier] = []
    /// UIKit outlet property names that DID get an identifier assignment.
    var assignedOutletNames: Set<String> = []
    /// Property name -> control type, from declarations in this file. Used to
    /// kind-guess assignments like `payButton.accessibilityIdentifier = ...`
    /// where the statement itself carries no type information.
    var propertyKinds: [String: String] = [:]
    private let lineIndex: LineIndex

    init(relativePath: String, source: String) {
        self.relativePath = relativePath
        self.lineIndex = LineIndex(source)
        super.init(viewMode: .sourceAccurate)
    }

    // SwiftUI modifier calls: `.accessibilityIdentifier("id")`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            // Possibly a control call site: `Button("Start") { ... }`.
            if let callName = Self.simpleCallName(node.calledExpression),
               ControlKnowledge.swiftUIControls.contains(callName) {
                recordControlSite(callName: callName, call: node)
            }
            return .visitChildren
        }
        let name = member.declName.baseName.text
        switch name {
        case "accessibilityIdentifier", "accessibilityLabel":
            let flavor: RawHit.Flavor = name == "accessibilityIdentifier" ? .identifier : .label
            let literal = Self.firstStringLiteral(in: node.arguments)
            let ctx = enclosingContext(of: node)
            let statementOffset = ctx.codeBlockItemOffset
                .map(String.init) ?? "\(node.positionAfterSkippingLeadingTrivia.utf8Offset)"
            // Point at the modifier name token, not the whole chain: the outer
            // call node starts where the chain starts.
            let position = lineIndex.lineColumn(
                utf8Offset: member.declName.positionAfterSkippingLeadingTrivia.utf8Offset
            )
            hits.append(RawHit(
                flavor: flavor,
                value: literal,
                file: relativePath,
                line: position.line,
                column: position.column,
                symbol: ctx.symbol,
                kindGuess: swiftUIKindGuess(call: node),
                groupKey: "call:\(relativePath):\(statementOffset)"
            ))
        default:
            // A modifier call on some chain; if the chain head is a known
            // control, remember it as a potential missing-identifier site.
            if let callName = Self.simpleCallName(node.calledExpression),
               ControlKnowledge.swiftUIControls.contains(callName) {
                recordControlSite(callName: callName, call: node)
            }
            break
        }
        return .visitChildren
    }

    // UIKit assignments: `x.accessibilityIdentifier = "id"` (SequenceExpr).
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() where element.is(AssignmentExprSyntax.self) {
            guard index > 0, index + 1 < elements.count else { continue }
            guard let lhs = elements[index - 1].as(MemberAccessExprSyntax.self) else { continue }
            let memberName = lhs.declName.baseName.text
            guard memberName == "accessibilityIdentifier" || memberName == "accessibilityLabel" else { continue }
            let flavor: RawHit.Flavor = memberName == "accessibilityIdentifier" ? .identifier : .label
            let rhs = elements[index + 1]
            let literal = rhs.as(StringLiteralExprSyntax.self).flatMap(Self.literalText)
            let ctx = enclosingContext(of: node)
            let root = Self.basePropertyName(lhs.base)
            if flavor == .identifier, let root {
                assignedOutletNames.insert(root)
            }
            let suffix = root ?? "anon\(node.positionAfterSkippingLeadingTrivia.utf8Offset)"
            hits.append(RawHit(
                flavor: flavor,
                value: literal,
                file: relativePath,
                line: lineIndex.lineColumn(utf8Offset: element.positionAfterSkippingLeadingTrivia.utf8Offset).line,
                column: lineIndex.lineColumn(utf8Offset: element.positionAfterSkippingLeadingTrivia.utf8Offset).column,
                symbol: ctx.symbol,
                kindGuess: uiKitKindGuess(ctx: ctx, statement: node, lhsRoot: root),
                groupKey: "lhs:\(relativePath):\(ctx.symbol):\(suffix)"
            ))
        }
        return .visitChildren
    }

    // UIKit control-typed property declarations.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.bindings.first else { return .visitChildren }
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { return .visitChildren }
        let propertyName = pattern.identifier.text
        // Remember declared or inferred control types for later kind guesses.
        if let annotation = binding.typeAnnotation {
            let baseType = SelfTrimming.trimmed(annotation.type.description)
            if ControlKnowledge.uiKitControls.contains(baseType) {
                propertyKinds[propertyName] = baseType
            }
        } else if let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let name = Self.simpleCallName(initializer.calledExpression),
                  ControlKnowledge.uiKitControls.contains(name) {
            propertyKinds[propertyName] = name
        }
        // Both annotated (`var x: UIButton!`) and inferred
        // (`let x = UIButton(type:)`) control properties are candidates.
        guard let controlType = propertyKinds[propertyName] else { return .visitChildren }
        let ctx = enclosingContext(of: node)
        let symbol = ctx.symbol.isEmpty
            ? pattern.identifier.text
            : "\(ctx.symbol).\(pattern.identifier.text)"
        outletCandidates.append(MissingIdentifier(
            kind: controlType,
            file: relativePath,
            line: lineIndex.lineColumn(utf8Offset: binding.pattern.positionAfterSkippingLeadingTrivia.utf8Offset).line,
            column: lineIndex.lineColumn(utf8Offset: binding.pattern.positionAfterSkippingLeadingTrivia.utf8Offset).column,
            symbol: symbol,
            reason: "uikit-property",
            hasLabel: false
        ))
        return .visitChildren
    }

    private func recordControlSite(callName: String, call: FunctionCallExprSyntax) {
        let ctx = enclosingContext(of: call)
        let statementOffset = ctx.codeBlockItemOffset
            .map(String.init) ?? "\(call.positionAfterSkippingLeadingTrivia.utf8Offset)"
        let position = lineIndex.lineColumn(utf8Offset: call.positionAfterSkippingLeadingTrivia.utf8Offset)
        controlSites.append(ControlCallSite(
            kind: callName,
            file: relativePath,
            line: position.line,
            column: position.column,
            symbol: ctx.symbol,
            groupKey: "call:\(relativePath):\(statementOffset)",
            hasIdentifierHit: false,
            hasLabelHit: false
        ))
    }

    // MARK: - Kind guesses

    private func swiftUIKindGuess(call: FunctionCallExprSyntax) -> String {
        // Walk down the modifier chain looking for a known control name:
        // `Text("hi").font(.title).accessibilityIdentifier("t")` -> "Text".
        var current: ExprSyntax? = call.calledExpression.as(MemberAccessExprSyntax.self)?.base
        var steps = 0
        while let expr = current, steps < 64 {
            steps += 1
            if let inner = expr.as(FunctionCallExprSyntax.self) {
                if let name = Self.simpleCallName(inner.calledExpression),
                   ControlKnowledge.swiftUIControls.contains(name) {
                    return name
                }
                current = inner.calledExpression
            } else if let member = expr.as(MemberAccessExprSyntax.self) {
                current = member.base
            } else if let chain = expr.as(OptionalChainingExprSyntax.self) {
                current = chain.expression
            } else if let unwrap = expr.as(ForceUnwrapExprSyntax.self) {
                current = unwrap.expression
            } else {
                current = nil
            }
        }
        return "Unknown"
    }

    private func uiKitKindGuess(ctx: EnclosingContext, statement: SequenceExprSyntax, lhsRoot: String?) -> String {
        if let lhsRoot, let declared = propertyKinds[lhsRoot] {
            return declared
        }
        if let type = ctx.variableTypeText, ControlKnowledge.uiKitControls.contains(type) {
            return type
        }
        // Look for a constructor call in the statement: `x = UIButton(type: .system)`.
        for element in statement.elements {
            if let call = element.as(FunctionCallExprSyntax.self),
               let name = Self.simpleCallName(call.calledExpression),
               ControlKnowledge.uiKitControls.contains(name) {
                return name
            }
        }
        return "Unknown"
    }
}

// MARK: - Position and context

/// Byte-offset based line/column index. Columns are 1-based and counted in
/// UTF-8 bytes (documented in README).
struct LineIndex {
    private let lineStarts: [Int]

    init(_ source: String) {
        var starts: [Int] = [0]
        var offset = 0
        for byte in source.utf8 {
            if byte == 0x0A { starts.append(offset + 1) }
            offset += 1
        }
        lineStarts = starts
    }

    func lineColumn(utf8Offset: Int) -> (line: Int, column: Int) {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= utf8Offset { low = mid } else { high = mid - 1 }
        }
        return (low + 1, utf8Offset - lineStarts[low] + 1)
    }
}

/// Enclosing-declaration context derived by walking up the syntax tree.
struct EnclosingContext {
    var typeName: String?
    var memberName: String?
    var variableTypeText: String?
    var codeBlockItemOffset: Int?

    var symbol: String {
        switch (typeName, memberName) {
        case let (.some(t), .some(m)): return "\(t).\(m)"
        case let (.some(t), nil): return t
        case let (nil, .some(m)): return m
        case (nil, nil): return ""
        }
    }
}

/// Walk up from `node` to find the nearest enclosing type, member declaration,
/// and statement, so anchors like `SettingsView.notificationsToggle` can be
/// derived from pure syntax context.
func enclosingContext(of node: some SyntaxProtocol) -> EnclosingContext {
    var ctx = EnclosingContext()
    var current: Syntax? = Syntax(node)
    while let parent = current?.parent {
        current = parent
        switch parent.kind {
        case .classDecl, .structDecl, .enumDecl, .actorDecl, .extensionDecl:
            if ctx.typeName == nil, let named = parent.asProtocol(NamedDeclSyntax.self) {
                ctx.typeName = named.name.text
            }
        case .functionDecl:
            if ctx.memberName == nil, let fn = parent.as(FunctionDeclSyntax.self) {
                ctx.memberName = fn.name.text
            }
        case .variableDecl:
            if let variable = parent.as(VariableDeclSyntax.self) {
                if ctx.memberName == nil,
                   let binding = variable.bindings.first,
                   let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                    ctx.memberName = pattern.identifier.text
                }
                if ctx.variableTypeText == nil {
                    if let typeText = variable.bindings.first?.typeAnnotation?.type.description {
                        ctx.variableTypeText = SelfTrimming.trimmed(typeText)
                    }
                }
            }
        case .codeBlockItem:
            if ctx.codeBlockItemOffset == nil {
                ctx.codeBlockItemOffset = parent.positionAfterSkippingLeadingTrivia.utf8Offset
            }
        default:
            break
        }
    }
    return ctx
}

enum SelfTrimming {
    /// Trim optionals/generics and take the last path component of a type name:
    /// `UIButton!` -> `UIButton`, `UIKit.UIButton` -> `UIButton`.
    static func trimmed(_ text: String) -> String {
        var t = text
        while t.hasSuffix("?") || t.hasSuffix("!") { t.removeLast() }
        if let generic = t.firstIndex(of: "<") { t = String(t[..<generic]) }
        if let dot = t.lastIndex(of: ".") { t = String(t[t.index(after: dot)...]) }
        return t
    }
}

extension AccessibilityVisitor {
    /// The first string-literal argument of a call, when statically known.
    static func firstStringLiteral(in arguments: LabeledExprListSyntax) -> String? {
        for argument in arguments {
            if let literal = argument.expression.as(StringLiteralExprSyntax.self) {
                return literalText(literal)
            }
        }
        return nil
    }

    /// Concatenate plain string segments; nil for interpolated/dynamic literals.
    static func literalText(_ literal: StringLiteralExprSyntax) -> String? {
        var text = ""
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let segment):
                text += segment.content.text
            default:
                return nil
            }
        }
        return text
    }

    /// Simple call name for `Foo(...)` or `Module.Foo(...)`.
    static func simpleCallName(_ expression: ExprSyntax) -> String? {
        if let ref = expression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// Innermost base property name of a member-access chain, e.g. for
    /// `self.loginButton!.accessibilityLabel` -> `loginButton`.
    static func basePropertyName(_ expression: ExprSyntax?) -> String? {
        var current = expression
        var steps = 0
        while let expr = current, steps < 64 {
            steps += 1
            if let member = expr.as(MemberAccessExprSyntax.self) {
                current = member.base
            } else if let chain = expr.as(OptionalChainingExprSyntax.self) {
                current = chain.expression
            } else if let unwrap = expr.as(ForceUnwrapExprSyntax.self) {
                current = unwrap.expression
            } else if let ref = expr.as(DeclReferenceExprSyntax.self) {
                return ref.baseName.text
            } else {
                return nil
            }
        }
        return nil
    }
}
