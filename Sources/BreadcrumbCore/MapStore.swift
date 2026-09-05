import Foundation

/// Reads and writes the breadcrumb map under `.breadcrumb/` (or a custom
/// `--out` directory). Writes are atomic (temp file + rename) and the content
/// is deterministic: same inputs, same bytes — no timestamps, sorted arrays,
/// sorted JSON keys.
public enum MapStore {
    public static let elementsFile = "elements.json"
    public static let testsFile = "tests.json"
    public static let orphansFile = "orphans.json"
    public static let missingFile = "missing-identifiers.json"
    public static let indexFile = "index.json"

    public struct Index: Codable, Equatable {
        public var version: Int
        public var tool: String
        public var sourceRoot: String
        public var testGlobs: [String]
        public var excludes: [String]
        public var counts: [String: Int]

        public init(
            version: Int, tool: String, sourceRoot: String,
            testGlobs: [String], excludes: [String], counts: [String: Int]
        ) {
            self.version = version
            self.tool = tool
            self.sourceRoot = sourceRoot
            self.testGlobs = testGlobs
            self.excludes = excludes
            self.counts = counts
        }
    }

    // MARK: - Write

    public static func write(_ map: BreadcrumbMap, index: Index, to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAtomic(encode(map.elements), to: directory.appendingPathComponent(elementsFile))
        try writeAtomic(encode(map.tests), to: directory.appendingPathComponent(testsFile))
        try writeAtomic(encode(map.orphans), to: directory.appendingPathComponent(orphansFile))
        try writeAtomic(encode(map.missingIdentifiers), to: directory.appendingPathComponent(missingFile))
        try writeAtomic(encode(index), to: directory.appendingPathComponent(indexFile))
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// Write via a temp file in the same directory, then rename over the
    /// destination — readers never observe a torn file.
    static func writeAtomic(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(getpid())")
        try data.write(to: temp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try? fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
    }

    // MARK: - Read

    public static func load(from directory: URL) throws -> (map: BreadcrumbMap, index: Index?) {
        let elements = try read([ElementRecord].self, directory.appendingPathComponent(elementsFile)) ?? []
        let tests = try read([ElementTests].self, directory.appendingPathComponent(testsFile)) ?? []
        let orphans = try read([OrphanLiteral].self, directory.appendingPathComponent(orphansFile)) ?? []
        let missing = try read([MissingIdentifier].self, directory.appendingPathComponent(missingFile)) ?? []
        let index: Index? = try read(Index.self, directory.appendingPathComponent(indexFile))
        let sourceRoot = index?.sourceRoot ?? directory.path
        let map = BreadcrumbMap(
            sourceRoot: sourceRoot,
            elements: elements, tests: tests, orphans: orphans, missingIdentifiers: missing
        )
        return (map, index)
    }

    /// Resolve the map directory the same way the CLI does: explicit `--out`
    /// wins, otherwise `.breadcrumb` relative to the working directory.
    public static func resolveDirectory(explicit: String?) -> URL {
        if let explicit {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(MapFormat.defaultDirectoryName, isDirectory: true)
    }

    private static func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
