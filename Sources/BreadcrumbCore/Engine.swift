import Foundation

/// Query engine over a loaded map. The CLI and the MCP server both consume
/// these methods; each returns a structured result plus a ready-to-print JSON
/// rendering, so the two surfaces cannot drift.
public struct Engine {
    public var map: BreadcrumbMap
    /// Directory queries are run from (used for git operations).
    public var workingDirectory: URL

    public init(map: BreadcrumbMap, workingDirectory: URL) {
        self.map = map
        self.workingDirectory = workingDirectory
    }

    public static func load(mapDirectory explicit: String?, workingDirectory: URL) throws -> Engine {
        let directory = MapStore.resolveDirectory(explicit: explicit)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw BreadcrumbError("no map found at \(directory.path). Run `breadcrumb crawl <sourceRoot>` first.")
        }
        let (map, _) = try MapStore.load(from: directory)
        return Engine(map: map, workingDirectory: workingDirectory)
    }

    // MARK: - where-is

    public struct WhereIsResult: Codable, Equatable {
        public var identifier: String
        public var elements: [ElementRecord]
        public var tests: [TestReference]
    }

    /// All elements carrying the identifier, plus the tests that reference it.
    public func whereIs(_ identifier: String) throws -> WhereIsResult {
        let elements = map.elements.filter { $0.identifier == identifier }
        guard !elements.isEmpty else {
            throw BreadcrumbError("no element has identifier '\(identifier)'. Check the spelling or run `breadcrumb crawl` again.")
        }
        let tests = map.tests.first { $0.identifier == identifier }?.tests ?? []
        return WhereIsResult(identifier: identifier, elements: elements, tests: tests)
    }

    // MARK: - what-renders

    public struct WhatRendersResult: Codable, Equatable {
        public var target: String
        public var elements: [ElementRecord]
    }

    /// Elements anchored in a symbol (`SettingsView.body`,
    /// `SettingsView.notificationsToggle`, or a whole type `SettingsView`) or a
    /// file path (relative to the source root, suffix-matched).
    public func whatRenders(_ target: String) throws -> WhatRendersResult {
        var elements = map.elements.filter { $0.symbol == target || $0.symbol.hasPrefix(target + ".") }
        if elements.isEmpty {
            // File target: exact relative path or unambiguous suffix.
            elements = map.elements.filter { element in
                element.file == target
                    || element.file.hasSuffix("/" + target)
                    || target.hasSuffix("/" + element.file)
            }
        }
        guard !elements.isEmpty else {
            throw BreadcrumbError("no known elements anchored in '\(target)'. Try a type, Type.member anchor, or a crawled file path.")
        }
        return WhatRendersResult(target: target, elements: elements)
    }

    // MARK: - affected-tests

    public struct AffectedTest: Codable, Equatable {
        public var identifier: String
        public var file: String
        public var line: Int
    }

    public struct AffectedTestsResult: Codable, Equatable {
        public var changedFiles: [String]
        public var affectedElements: [ElementRecord]
        public var tests: [AffectedTest]
    }

    /// Changed files → elements anchored in them → deduplicated test list.
    /// - `ref`: compare working tree against a git ref.
    /// - `files`: explicit override (comma-separated from the CLI).
    public func affectedTests(ref: String?, files: [String]?) throws -> AffectedTestsResult {
        let changed: [String]
        if let files, !files.isEmpty {
            changed = files
        } else {
            // Our own map artifacts are not source; never report them.
            changed = try GitDiff.changedFiles(workingDirectory: workingDirectory, ref: ref)
                .files
                .filter { !$0.hasPrefix(".breadcrumb/") }
        }
        var affected: [ElementRecord] = []
        for element in map.elements {
            if changed.contains(where: { GitDiff.touches(elementFile: element.file, changedFile: $0) }) {
                affected.append(element)
            }
        }
        var seen = Set<String>()
        var tests: [AffectedTest] = []
        for element in affected.sorted(by: order) {
            guard let references = map.tests.first(where: { $0.identifier == element.identifier })?.tests else { continue }
            for reference in references {
                let key = "\(reference.file):\(reference.line):\(element.identifier)"
                guard seen.insert(key).inserted else { continue }
                tests.append(AffectedTest(identifier: element.identifier, file: reference.file, line: reference.line))
            }
        }
        tests.sort { ($0.file, $0.line, $0.identifier) < ($1.file, $1.line, $1.identifier) }
        return AffectedTestsResult(changedFiles: changed, affectedElements: affected, tests: tests)
    }

    private func order(_ lhs: ElementRecord, _ rhs: ElementRecord) -> Bool {
        (lhs.file, lhs.line, lhs.column, lhs.identifier) < (rhs.file, rhs.line, rhs.column, rhs.identifier)
    }

    // MARK: - missing-identifiers

    public struct MissingIdentifiersResult: Codable, Equatable {
        public var total: Int
        public var perFile: [FileReport]
        public struct FileReport: Codable, Equatable {
            public var file: String
            public var findings: [MissingIdentifier]
        }
    }

    /// Interactive-looking controls without an accessibilityIdentifier, grouped
    /// per file. The residual is the point: it is the team's automation debt,
    /// quantified.
    public func missingIdentifiers() -> MissingIdentifiersResult {
        let grouped = Dictionary(grouping: map.missingIdentifiers, by: \.file)
        let perFile = grouped
            .map { file, findings in
                MissingIdentifiersResult.FileReport(
                    file: file,
                    findings: findings.sorted { ($0.line, $0.column, $0.symbol) < ($1.line, $1.column, $1.symbol) }
                )
            }
            .sorted { $0.file < $1.file }
        return MissingIdentifiersResult(total: map.missingIdentifiers.count, perFile: perFile)
    }
}

// MARK: - JSON rendering shared by CLI and MCP

extension Encodable {
    /// Deterministic JSON: sorted keys, pretty printed, POSIX slashes.
    public func breadcrumbJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
