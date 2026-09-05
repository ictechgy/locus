import XCTest
@testable import BreadcrumbCore

/// Extraction accuracy: identifiers, labels, positions, symbol anchors, kind
/// guesses, and missing-identifier detection, for both SwiftUI and UIKit.
final class CrawlerTests: XCTestCase {
    let swiftUIFixture = """
    import SwiftUI

    struct SettingsScreen: View {
        @State private var notificationsOn = true

        var notificationsToggle: some View {
            Toggle("Notifications", isOn: $notificationsOn)
                .accessibilityLabel("Allow notifications")
                .accessibilityIdentifier("settings.notifications")
        }

        var body: some View {
            VStack {
                notificationsToggle
                Button("Sign in") {}
                    .accessibilityIdentifier("settings.signIn")
                Text("Welcome").font(.title).accessibilityIdentifier("settings.title")
                Slider(value: .constant(0.5))
            }
        }
    }
    """

    let uiKitFixture = """
    import UIKit

    final class LoginViewController: UIViewController {
        @IBOutlet var loginButton: UIButton!
        @IBOutlet var signupButton: UIButton!
        let forgotButton = UIButton(type: .system)

        override func viewDidLoad() {
            super.viewDidLoad()
            loginButton.setTitle("Log in", for: .normal)
            loginButton.accessibilityLabel = "Log in"
            loginButton.accessibilityIdentifier = "login.submit"
            forgotButton.setTitle("Forgot?", for: .normal)
            forgotButton.accessibilityIdentifier = "login.forgot"
        }
    }
    """

    func testSwiftUIExtraction() throws {
        let root = Fixture.makeTree("swiftui", files: [
            "Sources/SettingsScreen.swift": swiftUIFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        XCTAssertEqual(map.elements.count, 3, "expected exactly 3 identified elements: \(map.elements.map({ $0.identifier }))")

        let toggle = try XCTUnwrap(map.elements.first { $0.identifier == "settings.notifications" })
        XCTAssertEqual(toggle.file, "Sources/SettingsScreen.swift")
        XCTAssertEqual(toggle.line, Fixture.line(of: ".accessibilityIdentifier(\"settings.notifications\")", in: swiftUIFixture))
        XCTAssertEqual(toggle.symbol, "SettingsScreen.notificationsToggle", "anchor must be enclosing type + enclosing property")
        XCTAssertEqual(toggle.kind, "Toggle")
        XCTAssertEqual(toggle.label, "Allow notifications", "label from the same modifier chain must attach")
        XCTAssertEqual(toggle.confidence, "high")

        let button = try XCTUnwrap(map.elements.first { $0.identifier == "settings.signIn" })
        XCTAssertEqual(button.symbol, "SettingsScreen.body")
        XCTAssertEqual(button.kind, "Button")
        XCTAssertNil(button.label)

        let text = try XCTUnwrap(map.elements.first { $0.identifier == "settings.title" })
        XCTAssertEqual(text.kind, "Text", "kind guess must walk down modifier chains (Text().font().a11yId)")
    }

    func testUIKitExtraction() throws {
        let root = Fixture.makeTree("uikit", files: [
            "Sources/LoginViewController.swift": uiKitFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        let submit = try XCTUnwrap(map.elements.first { $0.identifier == "login.submit" })
        XCTAssertEqual(submit.file, "Sources/LoginViewController.swift")
        XCTAssertEqual(submit.line, Fixture.line(of: "loginButton.accessibilityIdentifier", in: uiKitFixture))
        XCTAssertEqual(submit.symbol, "LoginViewController.viewDidLoad", "anchor must be enclosing type + enclosing func")
        XCTAssertEqual(submit.kind, "UIButton", "kind from the property declaration's control type")
        XCTAssertEqual(submit.label, "Log in", "label assignment on the same outlet attaches")

        let forgot = try XCTUnwrap(map.elements.first { $0.identifier == "login.forgot" })
        XCTAssertEqual(forgot.kind, "UIButton", "kind from inferred constructor type")
        XCTAssertNil(forgot.label)
        XCTAssertEqual(map.elements.count, 2)
    }

    func testMissingIdentifiers() throws {
        let root = Fixture.makeTree("missing", files: [
            "Sources/SettingsScreen.swift": swiftUIFixture,
            "Sources/LoginViewController.swift": uiKitFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)

        // SwiftUI: the Slider has no identifier modifier.
        let slider = try XCTUnwrap(
            map.missingIdentifiers.first { $0.kind == "Slider" },
            "unidentified Slider must be reported: \(map.missingIdentifiers)"
        )
        XCTAssertEqual(slider.file, "Sources/SettingsScreen.swift")
        XCTAssertEqual(slider.symbol, "SettingsScreen.body")
        XCTAssertEqual(slider.reason, "swiftui-call")

        // UIKit: signupButton is a control property never assigned an identifier.
        let signup = try XCTUnwrap(
            map.missingIdentifiers.first { $0.symbol.hasSuffix("signupButton") },
            "unassigned signupButton must be reported: \(map.missingIdentifiers)"
        )
        XCTAssertEqual(signup.kind, "UIButton")
        XCTAssertEqual(signup.reason, "uikit-property")

        // Identified controls must not leak into the missing report.
        XCTAssertFalse(map.missingIdentifiers.contains { $0.symbol.hasSuffix("loginButton") })
        XCTAssertFalse(map.missingIdentifiers.contains { $0.symbol.hasSuffix("forgotButton") })
        XCTAssertEqual(map.missingIdentifiers.count, 2)
    }

    func testDeterministicOutput() throws {
        let files = ["Sources/SettingsScreen.swift": swiftUIFixture, "Sources/LoginViewController.swift": uiKitFixture]
        let rootA = Fixture.makeTree("det-a", files: files)
        let rootB = Fixture.makeTree("det-b", files: files)
        defer { Fixture.cleanup(rootA); Fixture.cleanup(rootB) }
        let mapA = try Fixture.crawl(root: rootA)
        let mapB = try Fixture.crawl(root: rootB)
        XCTAssertEqual(mapA.elements, mapB.elements, "same input must yield byte-identical element order")
        XCTAssertEqual(mapA.missingIdentifiers, mapB.missingIdentifiers)
    }

    func testExcludeGlobs() throws {
        let root = Fixture.makeTree("exclude", files: [
            "Sources/SettingsScreen.swift": swiftUIFixture,
            "Generated/RocketGenerated.swift": swiftUIFixture,
        ])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root, excludes: ["Generated/*"])
        XCTAssertTrue(map.elements.allSatisfy { !$0.file.hasPrefix("Generated/") })
    }
}
