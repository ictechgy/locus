import Foundation

/// Minimal glob matcher supporting `*`, `?` and `**` (path segments).
/// Used for test-path matching (`--tests-glob`, default `*Tests*`).
public enum Glob {
    /// Match a POSIX-style path against a glob pattern.
    /// `*` matches any run of characters except `/`; `**` matches anything
    /// including `/`; `?` matches a single non-`/` character. A pattern without
    /// `/` is also tried against the whole path with `**/` prefixed, so
    /// `*Tests*` matches `Tests/FooTests.swift`.
    public static func matches(path: String, pattern: String) -> Bool {
        var pattern = pattern
        if pattern.hasPrefix("./") { pattern.removeFirst(2) }
        let pathParts = path.split(separator: "/").map(String.init)
        let patternParts = pattern.split(separator: "/").map(String.init)
        if matchSegments(pathParts, patternParts) { return true }
        if !pattern.contains("/") {
            return matchSegments(pathParts, ["**"] + patternParts)
        }
        return false
    }

    /// Match against any of the given patterns.
    public static func matchesAny(path: String, patterns: [String]) -> Bool {
        patterns.contains { matches(path: path, pattern: $0) }
    }

    private static func matchSegments(_ path: [String], _ pattern: [String]) -> Bool {
        if pattern.isEmpty { return path.isEmpty }
        let head = pattern[0]
        if head == "**" {
            // `**` matches zero or more segments.
            for i in 0...path.count {
                if matchSegments(Array(path[i...]), Array(pattern[1...])) { return true }
            }
            return false
        }
        if path.isEmpty { return false }
        if matchString(path[0], head) {
            return matchSegments(Array(path[1...]), Array(pattern[1...]))
        }
        return false
    }

    private static func matchString(_ string: String, _ pattern: String) -> Bool {
        // Classic iterative wildcard match within a single segment.
        var s = Array(string), p = Array(pattern)
        var si = 0, pi = 0
        var star: Int? = nil
        var mark = 0
        while si < s.count {
            if pi < p.count, (p[pi] == "?" || p[pi] == s[si]) {
                si += 1; pi += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = si; pi += 1
            } else if let st = star {
                pi = st + 1; mark += 1; si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// Filesystem walking helpers with deterministic ordering.
public enum SourceTree {
    /// Recursively collect `.swift` files under `root` (relative POSIX paths),
    /// skipping paths matching any exclude glob. Hidden directories and common
    /// build/VCS directories are always skipped unless explicitly included
    /// deeper. Result is sorted for determinism.
    public static func swiftFiles(
        under root: URL, excludes: [String]
    ) throws -> [String] {
        let fm = FileManager.default
        var results: [String] = []
        // Resolve symlinks once (/tmp and /var are symlinks on macOS) and build
        // relative paths incrementally — never by prefix arithmetic, which
        // breaks when enumeration resolves the root differently.
        let resolvedRoot = root.resolvingSymlinksInPath()
        let alwaysSkip = [".git", ".build", ".swiftpm", "DerivedData", "Pods", ".locus", "node_modules"]

        func walk(directory: URL, relativePrefix: String) throws {
            let entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entry.lastPathComponent
                if alwaysSkip.contains(name) { continue }
                if name.hasPrefix(".") { continue }
                let relative = relativePrefix.isEmpty ? name : relativePrefix + "/" + name
                if Glob.matchesAny(path: relative, patterns: excludes) { continue }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: entry.path, isDirectory: &isDir)
                if isDir.boolValue {
                    try walk(directory: entry, relativePrefix: relative)
                } else if name.hasSuffix(".swift") {
                    results.append(relative)
                }
            }
        }
        try walk(directory: resolvedRoot, relativePrefix: "")
        return results
    }

    /// Read a UTF-8 file, replacing invalid bytes instead of failing.
    public static func readSource(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8))
            ?? String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
    }
}
