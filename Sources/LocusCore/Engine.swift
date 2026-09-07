import Foundation

/// Query engine over a loaded map. The CLI and the MCP server both consume
/// these methods; each returns a structured result plus a ready-to-print JSON
/// rendering, so the two surfaces cannot drift.
public struct Engine {
    public var map: LocusMap
    /// Directory queries are run from (used for git operations).
    public var workingDirectory: URL

    public init(map: LocusMap, workingDirectory: URL) {
        self.map = map
        self.workingDirectory = workingDirectory
    }

    public static func load(mapDirectory explicit: String?, workingDirectory: URL) throws -> Engine {
        let directory = MapStore.resolveDirectory(explicit: explicit)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw LocusError("no map found at \(directory.path). Run `locus crawl <sourceRoot>` first.")
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
            throw LocusError("no element has identifier '\(identifier)'. Check the spelling or run `locus crawl` again.")
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
            throw LocusError("no known elements anchored in '\(target)'. Try a type, Type.member anchor, or a crawled file path.")
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
        var changed: [String]
        var repoRoot: String?
        if let files, !files.isEmpty {
            changed = files
        } else {
            // Our own map artifacts are not source; never report them.
            let diff = try GitDiff.changedFiles(workingDirectory: workingDirectory, ref: ref)
            repoRoot = diff.repositoryRoot
            changed = diff.files.filter { !$0.hasPrefix(".locus/") }
        }
        // Changed files are repo-root-relative, element files are sourceRoot-relative.
        // Align the frames of reference before matching.
        let prefix = Self.repoRelativePrefix(
            sourceRoot: map.sourceRoot, repoRoot: repoRoot, workingDirectory: workingDirectory
        )
        // With aligned frames (prefix != nil, possibly ""), match exactly:
        // suffix matching here would let a sibling directory's same-named
        // file hit this module's elements (invariant 3). The suffix fallback
        // exists only for a sourceRoot outside the repository.
        let changedSet = Set(changed)
        var affected: [ElementRecord] = []
        for element in map.elements {
            let repoPath: String
            if let prefix {
                repoPath = prefix.isEmpty ? element.file : prefix + "/" + element.file
            } else {
                repoPath = element.file
            }
            let touched = prefix != nil
                ? changedSet.contains(repoPath)
                : changed.contains { GitDiff.touches(elementFile: repoPath, changedFile: $0) }
            if touched { affected.append(element) }
        }
        let testsByIdentifier = Dictionary(
            map.tests.map { ($0.identifier, $0.tests) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        var tests: [AffectedTest] = []
        for element in affected.sorted(by: order) {
            guard let references = testsByIdentifier[element.identifier] else { continue }
            for reference in references {
                let key = "\(reference.file):\(reference.line):\(element.identifier)"
                guard seen.insert(key).inserted else { continue }
                tests.append(AffectedTest(identifier: element.identifier, file: reference.file, line: reference.line))
            }
        }
        tests.sort { ($0.file, $0.line, $0.identifier) < ($1.file, $1.line, $1.identifier) }
        return AffectedTestsResult(changedFiles: changed, affectedElements: affected, tests: tests)
    }

    /// element.file paths are relative to the crawled sourceRoot; git reports
    /// changes relative to the repository root. When the sourceRoot sits inside
    /// the repository, return its repo-relative prefix (`App` for a repo with
    /// `App/Sources/…`) so paths compare exactly. Suffix matching alone would
    /// let `OtherModule/Sources/X.swift` changes false-positive on
    /// `App/Sources/X.swift` elements. Returns `""` when the sourceRoot *is*
    /// the repository root (frames already aligned, element paths are
    /// repo-relative as-is), and nil when sourceRoot is not inside the
    /// repository (suffix matching then remains the fallback).
    static func repoRelativePrefix(sourceRoot: String, repoRoot: String?, workingDirectory: URL) -> String? {
        guard let repoRoot, !repoRoot.isEmpty else { return nil }
        var rootURL = URL(fileURLWithPath: sourceRoot, isDirectory: true)
        if !sourceRoot.hasPrefix("/") {
            rootURL = workingDirectory.appendingPathComponent(sourceRoot, isDirectory: true)
        }
        let resolvedSourceRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedRepoRoot = URL(fileURLWithPath: repoRoot, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        if resolvedSourceRoot == resolvedRepoRoot { return "" }
        guard resolvedSourceRoot.hasPrefix(resolvedRepoRoot + "/") else { return nil }
        return String(resolvedSourceRoot.dropFirst(resolvedRepoRoot.count + 1))
    }

    private func order(_ lhs: ElementRecord, _ rhs: ElementRecord) -> Bool {
        (lhs.file, lhs.line, lhs.column, lhs.identifier) < (rhs.file, rhs.line, rhs.column, rhs.identifier)
    }

    // MARK: - snapshot

    /// Match a runtime accessibility-tree dump against the static ledger.
    /// Identifier direct matches are `high`; unique label matches `medium`;
    /// everything else lands in the residuals — which are the point.
    public func matchSnapshot(nodes: [SnapshotNode]) -> SnapshotMatcher.Report {
        SnapshotMatcher().match(nodes: nodes, elements: map.elements)
    }

    /// Parse and match in one step (CLI/MCP shared path).
    public func matchSnapshot(dump: String) throws -> SnapshotMatcher.Report {
        matchSnapshot(nodes: try SnapshotDump.parse(dump))
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
    public func locusJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = MapFormat.jsonFormatting
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
