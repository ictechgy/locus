import XCTest
@testable import LocusCore

/// Command-line grammar: every locus option takes a value — a value-less
/// `--out` used to become the string "true" and write the map into ./true/.
final class ArgumentsTests: XCTestCase {
    private let grammar = CommandGrammar(positional: 1...1, valueOptions: ["out"], repeatableOptions: ["exclude"])

    func testValueOptionForms() throws {
        let spaceForm = try parse(["Sources", "--out", "/tmp/map"], grammar: grammar)
        XCTAssertEqual(spaceForm.value("out"), "/tmp/map")

        let equalsForm = try parse(["--out=/tmp/map", "Sources"], grammar: grammar)
        XCTAssertEqual(equalsForm.value("out"), "/tmp/map")
        XCTAssertEqual(equalsForm.positional, ["Sources"])
    }

    func testRepeatableOptionsCollect() throws {
        let args = try parse(["Sources", "--exclude", "Generated/*", "--exclude", "Vendor/*"], grammar: grammar)
        XCTAssertEqual(args.values("exclude"), ["Generated/*", "Vendor/*"])
    }

    func testMissingValueIsRejected() throws {
        // At the end of arguments…
        XCTAssertThrowsError(try parse(["Sources", "--out"], grammar: grammar)) { error in
            XCTAssertEqual("\(error)", "option --out requires a value.")
        }
        // …and when the next token looks like another option.
        XCTAssertThrowsError(try parse(["--out", "--exclude", "x", "Sources"], grammar: grammar))
    }

    func testEmptyInlineValueIsRejected() throws {
        XCTAssertThrowsError(try parse(["Sources", "--out="], grammar: grammar)) { error in
            XCTAssertEqual("\(error)", "option --out requires a non-empty value.")
        }
    }

    func testUnknownOptionIsRejected() throws {
        XCTAssertThrowsError(try parse(["Sources", "--nope", "x"], grammar: grammar)) { error in
            XCTAssertEqual("\(error)", "unknown option --nope. Try --help.")
        }
    }

    func testPositionalCountIsEnforced() throws {
        XCTAssertThrowsError(try parse([], grammar: grammar)) { error in
            XCTAssertTrue("\(error)".contains("expected 1–1 positional"), "\(error)")
        }
        XCTAssertThrowsError(try parse(["a", "b"], grammar: grammar))
        XCTAssertNoThrow(try parse(["a"], grammar: CommandGrammar(positional: 0...1, valueOptions: ["out"])))
    }
}
