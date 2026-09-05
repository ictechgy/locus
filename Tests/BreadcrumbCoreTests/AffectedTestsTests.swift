import XCTest
@testable import BreadcrumbCore

/// affected-tests integration: real git repository in a temp directory, dirty
/// working tree and ref-based diffs both drive the impact query.
final class AffectedTestsTests: XCTestCase {
    private let screenFixture = """
    import SwiftUI

    struct ProfileView: View {
        var body: some View {
            Button("Save") {}
                .accessibilityIdentifier("profile.save")
            Toggle("Notifications", isOn: .constant(true))
                .accessibilityIdentifier("profile.notifications")
        }
    }
    """

    private let testFixture = """
    import XCTest

    final class ProfileUITests: XCTestCase {
        func testSave() {
            let identifier = "profile.save"
            XCTAssertTrue(identifier.isEmpty == false)
        }
        func testNotifications() {
            let identifier = "profile.notifications"
            XCTAssertTrue(identifier.isEmpty == false)
        }
    }
    """

    private var repo: URL!
    private var engine: Engine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = Fixture.makeTree("repo", files: [
            "Sources/ProfileView.swift": screenFixture,
            "Tests/ProfileUITests.swift": testFixture,
        ])
        Fixture.git(["-c", "init.defaultBranch=main", "init"], in: repo)
        Fixture.git(["add", "."], in: repo)
        Fixture.gitIdentity(["commit", "-m", "init"], in: repo)
        let map = try Fixture.crawl(root: repo)
        let mapDir = repo.appendingPathComponent(".breadcrumb", isDirectory: true)
        let index = MapStore.Index(
            version: MapFormat.version, tool: MapFormat.tool, sourceRoot: repo.path,
            testGlobs: ["*Tests*"], excludes: [], counts: [:]
        )
        try MapStore.write(map, index: index, to: mapDir)
        engine = Engine(map: map, workingDirectory: repo)
    }

    override func tearDownWithError() throws {
        Fixture.cleanup(repo)
        repo = nil
        engine = nil
        try super.tearDownWithError()
    }

    func testDirtyWorkingTreeDrivesImpact() throws {
        // Make a tracked source file dirty.
        let screen = repo.appendingPathComponent("Sources/ProfileView.swift")
        let original = try String(contentsOf: screen, encoding: .utf8)
        try Data((original + "\n// tweak\n").utf8).write(to: screen)

        let result = try engine.affectedTests(ref: nil, files: nil)
        XCTAssertEqual(result.changedFiles, ["Sources/ProfileView.swift"])
        XCTAssertEqual(
            Set(result.affectedElements.map({ $0.identifier })),
            ["profile.save", "profile.notifications"],
            "both elements are anchored in the changed file"
        )
        XCTAssertEqual(
            Set(result.tests.map({ $0.identifier })),
            ["profile.save", "profile.notifications"],
            "each affected element contributes its referencing tests, deduplicated"
        )
        XCTAssertTrue(result.tests.allSatisfy { $0.file == "Tests/ProfileUITests.swift" })
    }

    func testExplicitFilesOverride() throws {
        let result = try engine.affectedTests(ref: nil, files: ["Sources/ProfileView.swift"])
        XCTAssertEqual(result.affectedElements.count, 2)
        XCTAssertEqual(result.tests.count, 2)
    }

    func testUnchangedTreeYieldsNoTests() throws {
        let result = try engine.affectedTests(ref: nil, files: nil)
        XCTAssertTrue(result.tests.isEmpty)
        XCTAssertTrue(result.affectedElements.isEmpty)
    }

    func testRefDiff() throws {
        // Commit a change, then diff against the previous commit via ref.
        let screen = repo.appendingPathComponent("Sources/ProfileView.swift")
        let original = try String(contentsOf: screen, encoding: .utf8)
        try Data((original + "\n// second tweak\n").utf8).write(to: screen)
        Fixture.git(["add", "."], in: repo)
        Fixture.gitIdentity(["commit", "-m", "tweak profile"], in: repo)

        let result = try engine.affectedTests(ref: "HEAD~1", files: nil)
        XCTAssertEqual(result.changedFiles, ["Sources/ProfileView.swift"])
        XCTAssertEqual(result.tests.count, 2)
    }
}
