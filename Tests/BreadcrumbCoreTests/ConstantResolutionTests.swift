import XCTest
@testable import BreadcrumbCore

/// Constant-table resolution: production codebases centralize identifiers in
/// constants (`enum A11yIdentifiers` + namespace structs / raw-value enums).
/// Discovered during P0 validation on element-x-ios (159 call sites, 1 literal).
final class ConstantResolutionTests: XCTestCase {
    private let constantFixture = """
    import SwiftUI

    enum A11yIdentifiers {
        static let roomScreen = RoomScreen()
        struct RoomScreen {
            let name = "room_screen-name"
            let topic = "room_screen-topic"
            func numpad(_ digit: Int) -> String { "numpad_\\(digit)" }
        }
    }

    enum ID: String {
        case pay = "checkout.pay"
    }

    enum ImplicitID: String {
        case submit
    }

    struct RoomScreen: View {
        var body: some View {
            VStack {
                TextField("Name", text: .constant(""))
                    .accessibilityIdentifier(A11yIdentifiers.roomScreen.name)
                Text("Topic")
                    .accessibilityIdentifier(A11yIdentifiers.roomScreen.topic)
                Button("Pay") {}
                    .accessibilityIdentifier(ID.pay)
                Button("Submit") {}
                    .accessibilityIdentifier(ImplicitID.submit)
                Button("Dial") {}
                    .accessibilityIdentifier(A11yIdentifiers.roomScreen.numpad(1))
            }
        }
    }
    """

    private let uiKitConstantFixture = """
    import UIKit

    final class CheckoutViewController: UIViewController {
        @IBOutlet var payButton: UIButton!
        @IBOutlet var helpButton: UIButton!

        override func viewDidLoad() {
            super.viewDidLoad()
            payButton.accessibilityIdentifier = ID.pay
        }
    }
    """

    func testNamespaceConstantResolution() throws {
        let root = Fixture.makeTree("constants", files: [
            "Sources/A11y.swift": constantFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let name = try XCTUnwrap(map.elements.first { $0.identifier == "room_screen-name" })
        XCTAssertEqual(name.kind, "TextField")
        XCTAssertEqual(name.symbol, "RoomScreen.body")
        XCTAssertEqual(name.file, "Sources/A11y.swift")
        // Position must point at the modifier, same as literal extraction.
        XCTAssertEqual(name.line, Fixture.line(of: ".accessibilityIdentifier(A11yIdentifiers.roomScreen.name)", in: constantFixture))

        let topic = try XCTUnwrap(map.elements.first { $0.identifier == "room_screen-topic" })
        XCTAssertEqual(topic.kind, "Text", "kind guess walks the modifier chain regardless of argument form")
    }

    func testRawValueAndImplicitEnumResolution() throws {
        let root = Fixture.makeTree("rawenum", files: [
            "Sources/A11y.swift": constantFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertEqual(map.elements.first { $0.identifier == "checkout.pay" }?.kind, "Button",
                       "explicit raw value resolves")
        XCTAssertEqual(map.elements.first { $0.identifier == "submit" }?.kind, "Button",
                       "implicit String raw value (= case name) resolves")
    }

    func testDynamicConstantIsAResidualNotAnElement() throws {
        let root = Fixture.makeTree("dynamic", files: [
            "Sources/A11y.swift": constantFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertFalse(map.elements.contains { $0.identifier.hasPrefix("numpad") },
                       "function-valued constants must not fabricate elements")
        XCTAssertTrue(
            map.missingIdentifiers.contains { $0.kind == "Button" && $0.line == Fixture.line(of: "Button(\"Dial\")", in: constantFixture) },
            "the unresolved Dial button surfaces as automation debt instead"
        )
    }

    func testUIKitConstantAssignmentResolves() throws {
        let root = Fixture.makeTree("uikit-const", files: [
            "Sources/A11y.swift": constantFixture,
            "Sources/CheckoutViewController.swift": uiKitConstantFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let pay = try XCTUnwrap(map.elements.first { $0.identifier == "checkout.pay" && $0.file == "Sources/CheckoutViewController.swift" })
        XCTAssertEqual(pay.kind, "UIButton")
        XCTAssertTrue(
            map.missingIdentifiers.contains { $0.symbol.hasSuffix("helpButton") },
            "a constant RHS still marks payButton assigned; helpButton stays debt"
        )
        XCTAssertFalse(map.missingIdentifiers.contains { $0.symbol.hasSuffix("payButton") })
    }

    func testConstantReferencesInTestsIndexLikeLiterals() throws {
        let testFixture = """
        import XCTest

        final class RoomUITests: XCTestCase {
            func testName() {
                let app = XCUIApplication()
                app.textFields[A11yIdentifiers.roomScreen.name].tap()
                app.buttons[ID.pay].tap()
            }
        }
        """
        let root = Fixture.makeTree("test-constants", files: [
            "Sources/A11y.swift": constantFixture,
            "Tests/RoomUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let nameRefs = try XCTUnwrap(map.tests.first { $0.identifier == "room_screen-name" })
        XCTAssertEqual(nameRefs.tests.first?.line, Fixture.line(of: "app.textFields[A11yIdentifiers.roomScreen.name]", in: testFixture))
        XCTAssertNotNil(map.tests.first { $0.identifier == "checkout.pay" })
    }

    func testOrphansRequireQueryPosition() throws {
        let testFixture = """
        import XCTest

        final class RoomUITests: XCTestCase {
            func testMisc() {
                let app = XCUIApplication()
                app.buttons["ghost.button"].tap()
                let bundleID = "com.apple.springboard"
                let domain = "Matrix.org"
            }
        }
        """
        let root = Fixture.makeTree("orphan-context", files: [
            "Tests/RoomUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertEqual(map.orphans.count, 1, "only the subscript-position ghost reports: \(map.orphans)")
        XCTAssertEqual(map.orphans.first?.literal, "ghost.button")
        XCTAssertEqual(map.orphans.first?.line, Fixture.line(of: "app.buttons[\"ghost.button\"]", in: testFixture))
    }

    func testNonInteractiveKindsAreNotAutomationDebt() throws {
        let fixture = """
        import SwiftUI

        struct InfoView: View {
            var body: some View {
                VStack {
                    Text("Plain static text")
                    Image(systemName: "star")
                    Button("Act") {}
                }
            }
        }
        """
        let root = Fixture.makeTree("kinds", files: ["Sources/InfoView.swift": fixture])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertEqual(map.missingIdentifiers.count, 1)
        XCTAssertEqual(map.missingIdentifiers.first?.kind, "Button",
                       "Text/Image stay matchable by label; only interactive controls are debt")
    }

    func testConstantCrawlIsDeterministic() throws {
        let files = [
            "Sources/A11y.swift": constantFixture,
            "Sources/CheckoutViewController.swift": uiKitConstantFixture,
        ]
        let rootA = Fixture.makeTree("const-det-a", files: files)
        let rootB = Fixture.makeTree("const-det-b", files: files)
        defer { Fixture.cleanup(rootA); Fixture.cleanup(rootB) }
        let mapA = try Fixture.crawl(root: rootA)
        let mapB = try Fixture.crawl(root: rootB)
        XCTAssertEqual(mapA.elements, mapB.elements)
        XCTAssertEqual(mapA.missingIdentifiers, mapB.missingIdentifiers)
    }

    func testConflictingDeclarationsDropTheEntry() throws {
        let fixture = """
        import SwiftUI

        enum Dup {
            static let a = "x.first"
            static let b = "y.second"
        }
        extension Dup {
            static let a = "x.conflict"
        }

        struct S: View {
            var body: some View {
                Button("1") {}.accessibilityIdentifier(Dup.a)
                Button("2") {}.accessibilityIdentifier(Dup.b)
            }
        }
        """
        let root = Fixture.makeTree("conflict", files: ["Sources/Dup.swift": fixture])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertNil(map.elements.first { $0.identifier.hasPrefix("x.") },
                     "ambiguous constants must not resolve")
        XCTAssertEqual(map.elements.first { $0.identifier == "y.second" }?.kind, "Button")
    }

    func testLabeledArgumentFormExtracts() throws {
        // Custom components take the identifier as a parameter, often nested
        // inside a styling call (element-x-ios pattern: `.compound(...)`).
        let fixture = """
        import SwiftUI

        enum A11yIdentifiers {
            static let loginScreen = LoginScreenIDs()
            struct LoginScreenIDs {
                let email = "login-email"
            }
        }

        struct LoginForm: View {
            var body: some View {
                TextField("Email", text: .constant(""))
                    .textFieldStyle(.compound(accessibilityIdentifier: A11yIdentifiers.loginScreen.email))
                SecureField("PIN", text: .constant(""))
                    .compound(accessibilityIdentifier: "login.pin", accessibilityLabel: "PIN entry")
            }
        }
        """
        let root = Fixture.makeTree("labeled", files: ["Sources/LoginForm.swift": fixture])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let email = try XCTUnwrap(map.elements.first { $0.identifier == "login-email" },
                                  "labeled-arg constant must extract: \(map.elements.map(\.identifier))")
        XCTAssertEqual(email.symbol, "LoginForm.body")
        XCTAssertNotNil(map.elements.first { $0.identifier == "login.pin" },
                        "labeled-arg literal must extract")
        let pin = try XCTUnwrap(map.elements.first { $0.identifier == "login.pin" })
        XCTAssertEqual(pin.label, "PIN entry", "labeled accessibilityLabel attaches to the same call")
    }

    func testBacktickedConstantNamesResolve() throws {
        let fixture = """
        import SwiftUI

        enum A11yIdentifiers {
            static let changeServerScreen = ChangeServer()
            struct ChangeServer {
                let server = "change_server-server"
                let `continue` = "change_server-continue"
            }
        }

        struct ServerSelectionScreen: View {
            var body: some View {
                TextField("URL", text: .constant(""), accessibilityIdentifier: A11yIdentifiers.changeServerScreen.server)
                Button("OK") {}
                    .accessibilityIdentifier(A11yIdentifiers.changeServerScreen.continue)
            }
        }
        """
        let root = Fixture.makeTree("backtick", files: ["Sources/S.swift": fixture])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertEqual(map.elements.filter { $0.identifier.hasPrefix("change_server") }.count, 2,
                       "backticked `continue` and labeled-arg `server` both resolve: \(map.elements.map(\.identifier))")
    }
}
