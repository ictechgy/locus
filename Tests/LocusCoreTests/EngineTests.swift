import XCTest
@testable import LocusCore

/// Query engine semantics on a loaded map.
final class EngineTests: XCTestCase {
    private func makeEngine() throws -> (Engine, URL) {
        let screen = """
        import SwiftUI

        struct ProfileView: View {
            var avatarToggle: some View {
                Toggle("Avatar", isOn: .constant(false))
                    .accessibilityIdentifier("profile.avatar")
            }
            var body: some View {
                avatarToggle
                Button("Save") {}
                    .accessibilityIdentifier("profile.save")
                Button("Help") {}
            }
        }

        struct BillingView: View {
            var body: some View {
                Button("Pay") {}
                    .accessibilityIdentifier("billing.pay")
            }
        }
        """
        let root = Fixture.makeTree("engine", files: ["Sources/ProfileView.swift": screen])
        defer { Fixture.cleanup(root) }
        let map = try Fixture.crawl(root: root)
        return (Engine(map: map, workingDirectory: root), root)
    }

    func testWhereIsReturnsElementsAndTests() throws {
        let (engine, _) = try makeEngine()
        let result = try engine.whereIs("profile.avatar")
        XCTAssertEqual(result.elements.first?.symbol, "ProfileView.avatarToggle")
        XCTAssertTrue(result.tests.isEmpty)
    }

    func testWhereIsUnknownIdentifierThrows() throws {
        let (engine, _) = try makeEngine()
        XCTAssertThrowsError(try engine.whereIs("ghost.element"))
    }

    func testWhatRendersByTypePrefix() throws {
        let (engine, _) = try makeEngine()
        let result = try engine.whatRenders("ProfileView")
        XCTAssertEqual(Set(result.elements.map({ $0.identifier })), ["profile.avatar", "profile.save"],
                       "querying a type must include all member anchors")
    }

    func testWhatRendersByMemberAnchor() throws {
        let (engine, _) = try makeEngine()
        let result = try engine.whatRenders("ProfileView.avatarToggle")
        XCTAssertEqual(result.elements.map({ $0.identifier }), ["profile.avatar"])
    }

    func testWhatRendersByFileSuffix() throws {
        let (engine, _) = try makeEngine()
        let result = try engine.whatRenders("ProfileView.swift")
        XCTAssertEqual(result.elements.count, 3,
                       "the single fixture file hosts all three elements")
    }

    func testWhatRendersUnknownTargetThrows() throws {
        let (engine, _) = try makeEngine()
        XCTAssertThrowsError(try engine.whatRenders("Nonexistent.thing"))
    }

    func testMissingIdentifiersGrouping() throws {
        let (engine, _) = try makeEngine()
        let result = engine.missingIdentifiers()
        XCTAssertEqual(result.total, 1, "the unidentified Help Button is the only missing control: \(result)")
        XCTAssertEqual(result.perFile.first?.file, "Sources/ProfileView.swift")
        XCTAssertEqual(result.perFile.first?.findings.first?.kind, "Button")
    }
}
