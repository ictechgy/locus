import Foundation
import SwiftSyntax
import SwiftParser

/// Kind names locus recognizes as controls.
public enum ControlKnowledge {
    /// SwiftUI element kinds (kind guessing + label context).
    public static let swiftUIKinds: Set<String> = [
        "Button", "Toggle", "TextField", "SecureField", "Slider", "Picker",
        "Stepper", "Link", "Menu", "NavigationLink", "DatePicker", "ColorPicker",
        "Image", "Text", "Label", "ProgressView", "TabView", "List",
    ]
    /// SwiftUI kinds that block automation when unidentified (tap/type targets).
    /// Static text/images can be matched by label instead — counting them as
    /// debt drowned real findings in 64% noise on a production codebase (P0).
    public static let swiftUIInteractiveKinds: Set<String> = [
        "Button", "Toggle", "TextField", "SecureField", "Slider", "Picker",
        "Stepper", "Link", "Menu", "NavigationLink", "DatePicker", "ColorPicker",
    ]
    /// UIKit control types (kind guessing for assignments and properties).
    public static let uiKitKinds: Set<String> = [
        "UIButton", "UISwitch", "UITextField", "UITextView", "UILabel",
        "UISlider", "UIStepper", "UIPickerView", "UIDatePicker", "UISegmentedControl",
        "UISearchBar", "UIPageControl", "UIImageView",
    ]
    /// UIKit control types that block automation when unidentified.
    public static let uiKitInteractiveKinds: Set<String> = [
        "UIButton", "UISwitch", "UITextField", "UITextView",
        "UISlider", "UIStepper", "UIPickerView", "UIDatePicker", "UISegmentedControl",
        "UISearchBar", "UIPageControl",
    ]
}

/// One raw accessibility-related finding before label/identifier merging.
public struct RawHit {
    enum Flavor { case identifier, label }
    var flavor: Flavor
    /// Statically known value: a plain string literal, or a member chain
    /// (`A11yIdentifiers.roomScreen.name`) resolved after the whole-repo
    /// constant table is complete. Nil for dynamic expressions — a documented
    /// static-analysis residual.
    var value: String?
    /// Unresolved member chain, when the argument was a constant reference.
    var chain: [String]?
    var file: String
    var line: Int
    var column: Int
    var symbol: String
    var kindGuess: String
    /// Groups hits that belong to the same element: one modifier chain /
    /// statement (SwiftUI), or the same outlet property inside the same member
    /// (UIKit).
    var groupKey: String
    var hasValue: Bool { value != nil }

    init(
        flavor: Flavor, value: String?, chain: [String]? = nil,
        file: String, line: Int, column: Int, symbol: String, kindGuess: String, groupKey: String
    ) {
        self.flavor = flavor
        self.value = value
        self.chain = chain
        self.file = file
        self.line = line
        self.column = column
        self.symbol = symbol
        self.kindGuess = kindGuess
        self.groupKey = groupKey
    }
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
    /// root and is what appears in output. Returns raw hits (constant chains
    /// unresolved — resolve them once the whole-repo `ConstantTable` is
    /// complete), control call sites, UIKit outlet candidates, assigned outlet
    /// names, and the file's constant declarations.
    public func crawlFile(source: String, relativePath: String) throws
        -> (hits: [RawHit], controlSites: [ControlCallSite], outletCandidates: [MissingIdentifier], assignedOutletNames: Set<String>, declarations: DeclarationCollector)
    {
        let tree = Parser.parse(source: source)
        let visitor = AccessibilityVisitor(relativePath: relativePath, source: source)
        visitor.walk(tree)
        let declarations = DeclarationCollector()
        declarations.walk(tree)
        return (visitor.hits, visitor.controlSites, visitor.outletCandidates, visitor.assignedOutletNames, declarations)
    }

    /// Crawl a whole source root.
    /// - Parameters:
    ///   - root: directory to crawl.
    ///   - excludes: glob patterns of paths to skip.
    /// - Returns: element records, missing-identifier findings (both sorted
    ///   deterministically), and the constant table built along the way (the
    ///   test scanner reuses it to resolve constant references in tests).
    public func crawl(root: URL, excludes: [String]) throws
        -> (elements: [ElementRecord], missing: [MissingIdentifier], constants: ConstantTable)
    {
        let files = try SourceTree.swiftFiles(under: root, excludes: excludes)
        let readRoot = root.resolvingSymlinksInPath()
        var allHits: [RawHit] = []
        var allSites: [ControlCallSite] = []
        var outletCandidates: [MissingIdentifier] = []
        var assignedNamesPerFile: [String: Set<String>] = [:]
        var constants = ConstantTable()
        for relative in files {
            let source = SourceTree.readSource(at: readRoot.appendingPathComponent(relative))
            let (hits, sites, outlets, assigned, declarations) = try crawlFile(source: source, relativePath: relative)
            constants.absorb(declarations)
            allHits.append(contentsOf: hits)
            allSites.append(contentsOf: sites)
            outletCandidates.append(contentsOf: outlets)
            assignedNamesPerFile[relative] = assigned
        }
        // Constant chains resolve only now: the table spans the whole crawl.
        allHits = allHits.map { hit in
            guard hit.value == nil, let chain = hit.chain else { return hit }
            var resolved = hit
            resolved.value = constants.resolve(chain: chain)
            return resolved
        }
        let records = Self.merge(hits: allHits).sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            if $0.column != $1.column { return $0.column < $1.column }
            return $0.identifier < $1.identifier
        }

        // Missing identifiers, SwiftUI side: control call sites whose statement
        // group never received an identifier hit.
        let identifierGroups = Set(allHits.filter { $0.flavor == .identifier && $0.hasValue }.map(\.groupKey))
        let labeledGroups = Set(allHits.filter { $0.flavor == .label && $0.hasValue }.map(\.groupKey))
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
        return (records, sortedMissing, constants)
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
                let label = labelHits.first { $0.hasValue }?.value
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

    // SwiftUI modifier calls: `.accessibilityIdentifier("id")` or
    // `.accessibilityIdentifier(A11yIdentifiers.roomScreen.name)`.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Labeled-argument form: custom components take the identifier as a
        // parameter — `.compound(labelText: …, accessibilityIdentifier: A11y.x)`.
        // Runs for every call; the modifier form's own argument is unlabeled,
        // so there is no double extraction.
        extractLabeledIdentifierArguments(of: node)
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            // Possibly a control call site: `Button("Start") { ... }`.
            if let callName = SyntaxText.simpleCallName(node.calledExpression),
               ControlKnowledge.swiftUIInteractiveKinds.contains(callName) {
                recordControlSite(callName: callName, call: node)
            }
            return .visitChildren
        }
        let name = member.declName.baseName.text
        switch name {
        case "accessibilityIdentifier", "accessibilityLabel":
            let flavor: RawHit.Flavor = name == "accessibilityIdentifier" ? .identifier : .label
            let argument = Self.argumentValue(in: node.arguments)
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
                value: argument.literal,
                chain: argument.chain,
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
            if let callName = SyntaxText.simpleCallName(node.calledExpression),
               ControlKnowledge.swiftUIInteractiveKinds.contains(callName) {
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
            let literal = rhs.as(StringLiteralExprSyntax.self).flatMap(SyntaxText.plainLiteral)
            let chain = literal == nil ? SyntaxText.memberChain(rhs) : nil
            let ctx = enclosingContext(of: node)
            let root = Self.basePropertyName(lhs.base)
            let hasValue = literal != nil || chain != nil
            if flavor == .identifier, hasValue, let root {
                assignedOutletNames.insert(root)
            }
            let suffix = root ?? "anon\(node.positionAfterSkippingLeadingTrivia.utf8Offset)"
            hits.append(RawHit(
                flavor: flavor,
                value: literal,
                chain: chain,
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
            let baseType = SyntaxText.trimmedTypeName(annotation.type.description)
            if ControlKnowledge.uiKitKinds.contains(baseType) {
                propertyKinds[propertyName] = baseType
            }
        } else if let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let name = SyntaxText.simpleCallName(initializer.calledExpression),
                  ControlKnowledge.uiKitKinds.contains(name) {
            propertyKinds[propertyName] = name
        }
        // Only interactive controls are automation debt: `let x: UIButton!`
        // without an identifier blocks automation; a UILabel does not.
        guard let controlType = propertyKinds[propertyName],
              ControlKnowledge.uiKitInteractiveKinds.contains(controlType) else { return .visitChildren }
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

    private func extractLabeledIdentifierArguments(of node: FunctionCallExprSyntax) {
        for argument in node.arguments {
            guard let label = argument.label else { continue }
            let name = SyntaxText.normalizedName(label.text)
            guard name == "accessibilityIdentifier" || name == "accessibilityLabel" else { continue }
            let flavor: RawHit.Flavor = name == "accessibilityIdentifier" ? .identifier : .label
            let literal = argument.expression.as(StringLiteralExprSyntax.self).flatMap(SyntaxText.plainLiteral)
            let chain = literal == nil ? SyntaxText.memberChain(argument.expression) : nil
            let ctx = enclosingContext(of: node)
            let statementOffset = ctx.codeBlockItemOffset
                .map(String.init) ?? "\(node.positionAfterSkippingLeadingTrivia.utf8Offset)"
            let position = lineIndex.lineColumn(
                utf8Offset: argument.positionAfterSkippingLeadingTrivia.utf8Offset
            )
            let kind = SyntaxText.simpleCallName(node.calledExpression)
                .map { ControlKnowledge.swiftUIKinds.contains($0) ? $0 : "Unknown" } ?? "Unknown"
            hits.append(RawHit(
                flavor: flavor,
                value: literal,
                chain: chain,
                file: relativePath,
                line: position.line,
                column: position.column,
                symbol: ctx.symbol,
                kindGuess: kind,
                groupKey: "call:\(relativePath):\(statementOffset)"
            ))
        }
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
                if let name = SyntaxText.simpleCallName(inner.calledExpression),
                   ControlKnowledge.swiftUIKinds.contains(name) {
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
        if let type = ctx.variableTypeText, ControlKnowledge.uiKitKinds.contains(type) {
            return type
        }
        // Look for a constructor call in the statement: `x = UIButton(type: .system)`.
        for element in statement.elements {
            if let call = element.as(FunctionCallExprSyntax.self),
               let name = SyntaxText.simpleCallName(call.calledExpression),
               ControlKnowledge.uiKitKinds.contains(name) {
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
                        ctx.variableTypeText = SyntaxText.trimmedTypeName(typeText)
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


extension AccessibilityVisitor {
    /// The first argument's statically known value: a plain string literal,
    /// or the unresolved member chain of a constant reference.
    static func argumentValue(in arguments: LabeledExprListSyntax) -> (literal: String?, chain: [String]?) {
        guard let first = arguments.first else { return (nil, nil) }
        if let literal = first.expression.as(StringLiteralExprSyntax.self) {
            return (SyntaxText.plainLiteral(literal), nil)
        }
        return (nil, SyntaxText.memberChain(first.expression))
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
