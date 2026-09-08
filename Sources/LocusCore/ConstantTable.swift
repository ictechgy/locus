import Foundation
import SwiftSyntax
import SwiftParser

/// Statically resolvable string constants collected from nominal-type member
/// declarations across a crawl.
///
/// Production codebases often centralize accessibility identifiers in
/// constants instead of inline string literals:
///
///     enum A11yIdentifiers {
///         static let roomScreen = RoomScreen()          // namespace alias
///         struct RoomScreen { let name = "room_screen-name" }
///     }
///     …
///     .accessibilityIdentifier(A11yIdentifiers.roomScreen.name)
///
/// `A11yIdentifiers.roomScreen.name` is fully resolvable from syntax alone —
/// no index store needed. Raw-value string enums resolve too
/// (`enum ID: String { case pay = "checkout.pay" }`, with the Swift rule that
/// a case without an explicit raw value uses the case name). Dynamic values
/// (functions, interpolated literals) do not resolve and stay residuals, per
/// the honest-limits contract.
///
/// Found on a real codebase during P0 validation: a 1,385-file production
/// app (element-x-ios) carries 159 identifier call sites of which exactly one
/// uses an inline literal — constant resolution is not a nice-to-have.
public struct ConstantTable {
    /// type name -> member name -> literal value. Conflicting declarations of
    /// the same (type, member) pair drop the entry: ambiguous beats wrong.
    private var memberLiterals: [String: [String: String]] = [:]
    /// type name -> member name -> aliased type name (`static let ns = Type()`).
    private var memberAliases: [String: [String: String]] = [:]
    private var ambiguous: Set<String> = []

    public init() {}

    public var isEmpty: Bool { memberLiterals.isEmpty && memberAliases.isEmpty }

    /// Type names usable as the root of a resolvable member chain.
    public var rootTypeNames: Set<String> {
        Set(memberLiterals.keys).union(memberAliases.keys)
    }

    /// Merge declarations collected from one parsed source file.
    public mutating func absorb(_ collected: DeclarationCollector) {
        for (typeName, member, value) in collected.literals {
            Self.insert(into: &memberLiterals, typeName: typeName, member: member, value: value, ambiguous: &ambiguous)
        }
        for (typeName, member, alias) in collected.aliases {
            Self.insert(into: &memberAliases, typeName: typeName, member: member, value: alias, ambiguous: &ambiguous)
        }
    }

    private static func insert(
        into table: inout [String: [String: String]], typeName: String, member: String, value: String, ambiguous: inout Set<String>
    ) {
        if let existing = table[typeName]?[member], existing != value {
            ambiguous.insert("\(typeName).\(member)")
            table[typeName]?[member] = nil
            return
        }
        table[typeName, default: [:]][member] = value
    }

    /// Resolve a dotted member chain like
    /// `["A11yIdentifiers", "roomScreen", "name"]` to its string constant.
    /// A leading module qualifier (`Module.A11yIdentifiers.…`) is tolerated.
    public func resolve(chain: [String]) -> String? {
        guard chain.count >= 2, chain.count <= 16 else { return nil }
        if let value = resolveRooted(chain) { return value }
        if chain.count >= 3 { return resolveRooted(Array(chain.dropFirst())) }
        return nil
    }

    private func resolveRooted(_ chain: [String]) -> String? {
        var currentType = chain[0]
        let members = chain.dropFirst()
        for (index, member) in members.enumerated() {
            let isLast = index == members.count - 1
            if isLast {
                guard let literal = memberLiterals[currentType]?[member],
                      !ambiguous.contains("\(currentType).\(member)") else { return nil }
                return literal
            }
            guard let next = memberAliases[currentType]?[member] else { return nil }
            currentType = next
        }
        return nil
    }
}

/// Collects constant declarations from one syntax tree. Lives outside
/// `ConstantTable` so a crawler can harvest declarations and hits from a
/// single parse pass and resolve the chains afterwards, when the whole-repo
/// table is complete.
public final class DeclarationCollector: SyntaxVisitor {
    /// (enclosing nominal type name, member name, string value)
    public var literals: [(String, String, String)] = []
    /// (enclosing nominal type name, member name, constructed type name)
    public var aliases: [(String, String, String)] = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// `case pay = "checkout.pay"` — and, when the enum's raw type is String,
    /// `case pay` (implicit raw value = case name, per Swift semantics).
    override public func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        guard let enumDecl = nearestNominalAncestor(of: Syntax(node)).flatMap({ $0.castIfEnumDecl() }) else {
            return .visitChildren
        }
        let enumName = enumDecl.name.text
        if let raw = node.rawValue?.value.as(StringLiteralExprSyntax.self),
           let text = SyntaxText.plainLiteral(raw) {
            literals.append((enumName, SyntaxText.normalizedName(node.name.text), text))
        } else if node.rawValue == nil, Self.hasStringRawType(enumDecl) {
            literals.append((enumName, SyntaxText.normalizedName(node.name.text), SyntaxText.normalizedName(node.name.text)))
        }
        return .visitChildren
    }

    /// `let/vars` inside a nominal type: string-literal members become
    /// constants, `static let ns = Type()` constructor members become aliases.
    /// Immutable bindings only — a `var` can be reassigned at runtime, and
    /// recording its initializer would put a maybe-stale value in the ledger
    /// with full confidence.
    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.text == "let" else { return .visitChildren }
        guard let typeName = nearestNominalAncestorTypeName(of: Syntax(node)) else {
            return .visitChildren
        }
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = SyntaxText.normalizedName(pattern.identifier.text)
            guard name != "_" else { continue }
            if let literal = binding.initializer?.value.as(StringLiteralExprSyntax.self),
               let text = SyntaxText.plainLiteral(literal) {
                literals.append((typeName, name, text))
            } else if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      let constructed = SyntaxText.simpleCallName(call.calledExpression),
                      constructed.first?.isUppercase == true {
                aliases.append((typeName, name, constructed))
            }
        }
        return .visitChildren
    }

    private static func hasStringRawType(_ enumDecl: EnumDeclSyntax) -> Bool {
        guard let inherited = enumDecl.inheritanceClause?.inheritedTypes else { return false }
        for type in inherited {
            if SyntaxText.trimmedTypeName(type.type.trimmedDescription) == "String" { return true }
        }
        return false
    }

    private func nearestNominalAncestorTypeName(of node: Syntax) -> String? {
        guard let named = nearestNominalAncestor(of: node) else { return nil }
        switch named.kind {
        case .extensionDecl:
            // Extensions carry an extended *type*, not a name.
            return SyntaxText.trimmedTypeName(named.cast(ExtensionDeclSyntax.self).extendedType.trimmedDescription)
        default:
            return named.asProtocol(NamedDeclSyntax.self)?.name.text
        }
    }

    private func nearestNominalAncestor(of node: Syntax) -> Syntax? {
        var current = node.parent
        while let parent = current {
            switch parent.kind {
            case .structDecl, .enumDecl, .classDecl, .actorDecl, .extensionDecl:
                return parent
            default:
                current = parent.parent
            }
        }
        return nil
    }
}

private extension Syntax {
    func castIfEnumDecl() -> EnumDeclSyntax? {
        kind == .enumDecl ? cast(EnumDeclSyntax.self) : nil
    }
}

/// Shared syntax helpers used by the crawler, scanner and constant table.
enum SyntaxText {
    /// Concatenate plain string segments; nil for interpolated/dynamic literals.
    static func plainLiteral(_ literal: StringLiteralExprSyntax) -> String? {
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
            return normalizedName(ref.baseName.text)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return normalizedName(member.declName.baseName.text)
        }
        return nil
    }

    /// Strip backticks from escaped identifiers (``let `continue` = …``):
    /// declaration tokens keep them, member-access tokens do not — both must
    /// produce the same table key.
    static func normalizedName(_ text: String) -> String {
        text.hasPrefix("`") && text.hasSuffix("`") ? String(text.dropFirst().dropLast()) : text
    }

    /// Trim optionals/generics and take the last path component of a type name.
    static func trimmedTypeName(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("?") || t.hasSuffix("!") { t.removeLast() }
        if let generic = t.firstIndex(of: "<") { t = String(t[..<generic]) }
        if let dot = t.lastIndex(of: ".") { t = String(t[t.index(after: dot)...]) }
        return t
    }

    /// Dotted components of a fully spelled-out member chain
    /// (`A11yIdentifiers.roomScreen.name`), root first. Nil unless the chain
    /// bottoms out in a plain identifier reference (not `self`, not a call).
    static func memberChain(_ expression: ExprSyntax) -> [String]? {
        var components: [String] = []
        var current: ExprSyntax? = expression
        var steps = 0
        while let expr = current, steps < 16 {
            steps += 1
            if let member = expr.as(MemberAccessExprSyntax.self) {
                components.append(SyntaxText.normalizedName(member.declName.baseName.text))
                current = member.base
            } else if let ref = expr.as(DeclReferenceExprSyntax.self) {
                components.append(SyntaxText.normalizedName(ref.baseName.text))
                return components.reversed()
            } else if let unwrap = expr.as(ForceUnwrapExprSyntax.self) {
                current = unwrap.expression
            } else if let chaining = expr.as(OptionalChainingExprSyntax.self) {
                current = chaining.expression
            } else {
                return nil
            }
        }
        return nil
    }
}
