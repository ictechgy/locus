import XCTest
@testable import LocusCore

/// Reverse index: literals in test files map back to elements; identifier-
/// shaped literals matching nothing are orphans.
final class ReverseIndexTests: XCTestCase {
    func testReverseIndexAndOrphans() throws {
        let testFixture = """
        import XCTest

        final class SettingsUITests: XCTestCase {
            func testToggle() {
                let app = XCUIApplication()
                app.switches["settings.notifications"].tap()
                app.buttons["settings.signIn"].tap()
                app.buttons["settings.avatar.refresh"].tap()
            }
        }
        """
        let sourceFixture = """
        import SwiftUI

        struct SettingsScreen: View {
            var body: some View {
                Button("Sign in") {}
                    .accessibilityIdentifier("settings.signIn")
            }
        }
        """
        // Note: settings.notifications is referenced in tests but defined in a
        // file we deliberately include below; settings.avatar.refresh exists
        // nowhere and must be reported as an orphan.
        let settingsFixture = """
        import SwiftUI

        struct ExtraScreen: View {
            var body: some View {
                Toggle("Notifications", isOn: .constant(true))
                    .accessibilityIdentifier("settings.notifications")
            }
        }
        """
        let root = Fixture.makeTree("reverse", files: [
            "Sources/SettingsScreen.swift": sourceFixture,
            "Sources/ExtraScreen.swift": settingsFixture,
            "Tests/SettingsUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        // Reverse index: per-identifier test references.
        XCTAssertEqual(Set(map.tests.map({ $0.identifier })), ["settings.notifications", "settings.signIn"])
        let toggleTests = try XCTUnwrap(map.tests.first { $0.identifier == "settings.notifications" })
        XCTAssertEqual(toggleTests.tests.count, 1)
        XCTAssertEqual(toggleTests.tests.first?.file, "Tests/SettingsUITests.swift")
        XCTAssertEqual(toggleTests.tests.first?.line, Fixture.line(of: "app.switches[\"settings.notifications\"]", in: testFixture))

        // Orphans: identifier-shaped, matches nothing.
        XCTAssertEqual(map.orphans.count, 1, "orphan literals: \(map.orphans)")
        XCTAssertEqual(map.orphans.first?.literal, "settings.avatar.refresh")
        XCTAssertEqual(map.orphans.first?.file, "Tests/SettingsUITests.swift")
    }

    func testConstantRefOrphansOnlyInQueryPosition() throws {
        // A constant that resolves to an unknown identifier is orphan debt
        // only where it is *used as* an identifier (subscript / matching
        // call). A plain `let label = A11y.ghost` binding is not a query.
        let sourceFixture = """
        import SwiftUI

        struct Screen: View {
            var body: some View {
                Button("Save") {}
                    .accessibilityIdentifier(A11y.known)
            }
        }

        enum A11y {
            static let known = "screen.save"
            static let ghost = "screen.ghost.button"
        }
        """
        let testFixture = """
        import XCTest

        final class ScreenUITests: XCTestCase {
            func testMix() {
                let label = A11y.ghost
                _ = label
                app.buttons[A11y.ghost].tap()
                app.buttons[A11y.known].tap()
            }
        }
        """
        let root = Fixture.makeTree("const-query", files: [
            "Sources/Screen.swift": sourceFixture,
            "Tests/ScreenUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        // A11y.known resolves to a real identifier and is used as a query.
        XCTAssertEqual(map.tests.map(\.identifier), ["screen.save"])

        // The ghost constant appears twice, but only the UI-query position
        // is orphan debt.
        XCTAssertEqual(map.orphans.count, 1, "orphans: \(map.orphans)")
        XCTAssertEqual(map.orphans.first?.literal, "screen.ghost.button")
        XCTAssertEqual(map.orphans.first?.line, Fixture.line(of: "app.buttons[A11y.ghost]", in: testFixture))
    }

    func testNonTestFilesAreNotScanned() throws {
        // A dotted string in app code must not become an orphan or a test ref;
        // only test-glob paths feed the reverse index.
        let sourceFixture = """
        import SwiftUI

        struct Screen: View {
            let analyticsKey = "settings.notifications"
            var body: some View {
                Button("Sign in") {}
                    .accessibilityIdentifier("settings.signIn")
            }
        }
        """
        let root = Fixture.makeTree("nontest", files: [
            "Sources/Screen.swift": sourceFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)
        XCTAssertTrue(map.tests.isEmpty)
        XCTAssertTrue(map.orphans.isEmpty)
    }

    func testIdentifierShapeHeuristic() {
        XCTAssertTrue(TestScanner.isIdentifierShaped("settings.notifications"))
        XCTAssertTrue(TestScanner.isIdentifierShaped("login_button"))
        XCTAssertFalse(TestScanner.isIdentifierShaped("Log in"))
        XCTAssertFalse(TestScanner.isIdentifierShaped("Pay"))
        XCTAssertFalse(TestScanner.isIdentifierShaped("AGENT10"))
        XCTAssertFalse(TestScanner.isIdentifierShaped("hi"))
        XCTAssertFalse(TestScanner.isIdentifierShaped("https://example.com"))
    }

    func testMapPersistenceRoundTripAndDeterminism() throws {
        let sourceFixture = """
        import SwiftUI

        struct Screen: View {
            var body: some View {
                Button("Sign in") {}
                    .accessibilityIdentifier("settings.signIn")
            }
        }
        """
        let root = Fixture.makeTree("persist", files: [
            "Sources/Screen.swift": sourceFixture,
            "Tests/ScreenUITests.swift": "import XCTest\nfinal class T: XCTestCase { func testA() { XCTAssertTrue(true) } }\n",
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let outA = root.appendingPathComponent("map-a", isDirectory: true)
        let outB = root.appendingPathComponent("map-b", isDirectory: true)
        let index = MapStore.Index(
            version: MapFormat.version, tool: MapFormat.tool, sourceRoot: root.path,
            testGlobs: ["*Tests*"], excludes: [], counts: ["elements": map.elements.count]
        )
        try MapStore.write(map, index: index, to: outA)
        try MapStore.write(map, index: index, to: outB)

        let bytesA = try Data(contentsOf: outA.appendingPathComponent("elements.json"))
        let bytesB = try Data(contentsOf: outB.appendingPathComponent("elements.json"))
        XCTAssertEqual(bytesA, bytesB, "map writes must be deterministic")

        let (reloaded, loadedIndex) = try MapStore.load(from: outA)
        XCTAssertEqual(reloaded.elements, map.elements)
        XCTAssertEqual(reloaded.tests, map.tests)
        XCTAssertEqual(loadedIndex.testGlobs, ["*Tests*"])
    }
}
