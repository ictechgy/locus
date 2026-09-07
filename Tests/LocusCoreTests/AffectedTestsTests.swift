import XCTest
@testable import LocusCore

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
        let mapDir = repo.appendingPathComponent(".locus", isDirectory: true)
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

    func testOptionLikeRefIsRejected() throws {
        // A ref starting with "-" is git argument injection (e.g. --output=);
        // it must be rejected, never passed through.
        XCTAssertThrowsError(try engine.affectedTests(ref: "--output=/tmp/evil", files: nil)) { error in
            XCTAssertTrue("\(error)".contains("invalid git ref"), "got: \(error)")
        }
        XCTAssertThrowsError(try engine.affectedTests(ref: "-O/orderfile", files: nil))
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

    func testRepoRootSourceRootAvoidsCrossModuleFalsePositives() throws {
        // Crawling from the repository root itself (the `locus crawl .` case):
        // element files are already repo-relative, so matching must be exact.
        // The suffix fallback would let a change to Other/Sources/ProfileView.swift
        // also hit the elements anchored in Sources/ProfileView.swift.
        let otherScreenFixture = """
        import SwiftUI

        struct OtherProfileView: View {
            var body: some View {
                Button("Pay") {}
                    .accessibilityIdentifier("other.pay")
            }
        }
        """
        let repoRoot = Fixture.makeTree("repo-root", files: [
            "Sources/ProfileView.swift": screenFixture,
            "Other/Sources/ProfileView.swift": otherScreenFixture,
            "Tests/ProfileUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(repoRoot) }
        Fixture.git(["-c", "init.defaultBranch=main", "init"], in: repoRoot)
        Fixture.git(["add", "."], in: repoRoot)
        Fixture.gitIdentity(["commit", "-m", "init"], in: repoRoot)

        let map = try Fixture.crawl(root: repoRoot)
        let rootEngine = Engine(map: map, workingDirectory: repoRoot)
        XCTAssertEqual(
            Engine.repoRelativePrefix(sourceRoot: map.sourceRoot, repoRoot: repoRoot.path, workingDirectory: repoRoot),
            ""
        )

        // Dirty a sibling directory's same-named file: it must affect only
        // its own module's element, never the Sources/ one.
        let other = repoRoot.appendingPathComponent("Other/Sources/ProfileView.swift")
        try Data((try String(contentsOf: other, encoding: .utf8) + "\n// tweak elsewhere\n").utf8).write(to: other)
        let elsewhere = try rootEngine.affectedTests(ref: nil, files: nil)
        XCTAssertEqual(elsewhere.changedFiles, ["Other/Sources/ProfileView.swift"])
        XCTAssertEqual(
            Set(elsewhere.affectedElements.map { $0.identifier }),
            ["other.pay"],
            "sibling-directory change must not hit Sources/ elements"
        )

        // Dirty the element's own file — now those hit too. Both files are
        // dirty at this point, so all three elements are affected.
        let own = repoRoot.appendingPathComponent("Sources/ProfileView.swift")
        try Data((try String(contentsOf: own, encoding: .utf8) + "\n// tweak own\n").utf8).write(to: own)
        let hit = try rootEngine.affectedTests(ref: nil, files: nil)
        XCTAssertEqual(
            Set(hit.affectedElements.map { $0.identifier }),
            ["profile.save", "profile.notifications", "other.pay"]
        )
    }

    func testNestedSourceRootAvoidsCrossModuleFalsePositives() throws {
        // sourceRoot nested inside the repo, with a sibling module that shares
        // file names. Suffix-only matching would report the other module's
        // change as affecting this module's elements.
        let nested = Fixture.makeTree("nested", files: [
            "App/Sources/ProfileView.swift": screenFixture,
            "Other/Sources/ProfileView.swift": screenFixture,
            "App/Tests/ProfileUITests.swift": testFixture,
        ])
        defer { Fixture.cleanup(nested) }
        Fixture.git(["-c", "init.defaultBranch=main", "init"], in: nested)
        Fixture.git(["add", "."], in: nested)
        Fixture.gitIdentity(["commit", "-m", "init"], in: nested)

        let appDir = nested.appendingPathComponent("App", isDirectory: true)
        let map = try Fixture.crawl(root: appDir)
        let nestedEngine = Engine(map: map, workingDirectory: nested)
        XCTAssertEqual(
            Engine.repoRelativePrefix(sourceRoot: map.sourceRoot, repoRoot: nested.path, workingDirectory: nested),
            "App"
        )

        // Dirty a *different* module's same-named file.
        let other = nested.appendingPathComponent("Other/Sources/ProfileView.swift")
        try Data((try String(contentsOf: other, encoding: .utf8) + "\n// tweak elsewhere\n").utf8).write(to: other)
        let elsewhere = try nestedEngine.affectedTests(ref: nil, files: nil)
        XCTAssertEqual(elsewhere.changedFiles, ["Other/Sources/ProfileView.swift"])
        XCTAssertTrue(elsewhere.affectedElements.isEmpty, "cross-module change must not hit App elements")

        // Dirty the element's own module — now it hits.
        let app = nested.appendingPathComponent("App/Sources/ProfileView.swift")
        try Data((try String(contentsOf: app, encoding: .utf8) + "\n// tweak in module\n").utf8).write(to: app)
        let own = try nestedEngine.affectedTests(ref: nil, files: nil)
        XCTAssertEqual(
            Set(own.affectedElements.map { $0.identifier }),
            ["profile.save", "profile.notifications"]
        )
    }
}
