import Foundation

/// Option grammar for one locus subcommand: which options take a value,
/// which of those repeat, and how many positional arguments are allowed.
/// Every option in locus takes a value — there are no boolean flags — so a
/// value-less `--out` or an empty `--out=` is a usage error, never the
/// string "true" or "".
public struct CommandGrammar {
    /// Allowed count of positional arguments, e.g. `1...1` or `0...1`.
    public let positional: ClosedRange<Int>
    public let valueOptions: Set<String>
    public let repeatableOptions: Set<String>

    public init(positional: ClosedRange<Int>, valueOptions: Set<String>, repeatableOptions: Set<String> = []) {
        self.positional = positional
        self.valueOptions = valueOptions
        self.repeatableOptions = repeatableOptions
    }
}

public enum ArgumentParseError: Error, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)
    case emptyValue(String)
    case positionalCount(got: Int, expected: ClosedRange<Int>)

    public var description: String {
        switch self {
        case .unknownOption(let option):
            return "unknown option \(option). Try --help."
        case .missingValue(let option):
            return "option \(option) requires a value."
        case .emptyValue(let option):
            return "option \(option) requires a non-empty value."
        case .positionalCount(let got, let expected):
            return "expected \(expected.lowerBound)–\(expected.upperBound) positional argument(s), got \(got). Try --help."
        }
    }
}

public struct ParsedArgs {
    public var positional: [String] = []
    public var options: [String: [String]] = [:]

    public init() {}

    public func value(_ name: String) -> String? { options[name]?.first }
    public func values(_ name: String) -> [String] { options[name] ?? [] }
}

/// Parse `--name value`, `--name=value` and positionals against a grammar.
/// Repeated options collect into lists; any deviation is an error — the
/// parser never guesses a value into existence.
public func parse(_ arguments: [String], grammar: CommandGrammar) throws -> ParsedArgs {
    var parsed = ParsedArgs()
    var index = 0
    while index < arguments.count {
        let token = arguments[index]
        guard token.hasPrefix("--") else {
            parsed.positional.append(token)
            index += 1
            continue
        }
        let body = String(token.dropFirst(2))
        let name: String
        let inlineValue: String?
        if let equals = body.firstIndex(of: "=") {
            name = String(body[..<equals])
            inlineValue = String(body[body.index(after: equals)...])
        } else {
            name = body
            inlineValue = nil
        }
        guard grammar.valueOptions.contains(name) || grammar.repeatableOptions.contains(name) else {
            throw ArgumentParseError.unknownOption("--\(name)")
        }
        let value: String
        if let inlineValue {
            guard !inlineValue.isEmpty else {
                throw ArgumentParseError.emptyValue("--\(name)")
            }
            value = inlineValue
        } else {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw ArgumentParseError.missingValue("--\(name)")
            }
            value = arguments[index + 1]
            index += 1
        }
        parsed.options[name, default: []].append(value)
        index += 1
    }
    guard grammar.positional.contains(parsed.positional.count) else {
        throw ArgumentParseError.positionalCount(got: parsed.positional.count, expected: grammar.positional)
    }
    return parsed
}
