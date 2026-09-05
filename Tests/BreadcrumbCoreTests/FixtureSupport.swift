import Foundation
import XCTest
@testable import BreadcrumbCore

/// Shared fixture helpers: temp source trees, marker-based line lookup, and a
/// tiny git driver for the affected-tests integration test.
enum Fixture {
    static func makeTree(_ name: String, files: [String: String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("breadcrumb-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relative, content) in files.sorted(by: { $0.key < $1.key }) {
            let url = root.appendingPathComponent(relative)
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(content.utf8).write(to: url)
        }
        return root
    }

    static func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// 1-based line number of the first line containing `marker`.
    static func line(of marker: String, in content: String) -> Int {
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains(marker) {
            return index + 1
        }
        fatalError("marker not found: \(marker)")
    }

    /// Crawl a fixture tree and scan tests in one go, like the CLI does.
    static func crawl(root: URL, testGlobs: [String] = ["*Tests*"], excludes: [String] = []) throws -> BreadcrumbMap {
        let (elements, missing) = try Crawler().crawl(root: root, excludes: excludes)
        let known = Set(elements.map(\.identifier))
        let (tests, orphans) = try TestScanner().scan(
            root: root, globs: testGlobs, excludes: excludes, knownIdentifiers: known
        )
        return BreadcrumbMap(
            sourceRoot: root.path,
            elements: elements, tests: tests, orphans: orphans, missingIdentifiers: missing
        )
    }

    @discardableResult
    static func git(_ arguments: [String], in directory: URL, expectSuccess: Bool = true) -> String {
        let (exit, stdout, stderr) = GitDiff.run(arguments: arguments, workingDirectory: directory)
        if expectSuccess {
            XCTAssertEqual(exit, 0, "git \(arguments.joined(separator: " ")) failed: \(stderr)")
        }
        return exit == 0 ? stdout : stderr
    }

    static func gitIdentity(_ arguments: [String], in directory: URL) -> String {
        git(["-c", "user.email=test@breadcrumb.local", "-c", "user.name=breadcrumb-test"] + arguments, in: directory)
    }
}
