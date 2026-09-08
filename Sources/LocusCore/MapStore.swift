import Foundation

/// Reads and writes the locus map under `.locus/` (or a custom
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

    public static func write(_ map: LocusMap, index: Index, to directory: URL) throws {
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
        encoder.outputFormatting = MapFormat.jsonFormatting
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// Write via a temp file in the same directory, then rename over the
    /// destination — readers never observe a torn file. Replacement failures
    /// propagate: a silent failure here would report a successful crawl
    /// whose map was never actually written.
    static func writeAtomic(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(getpid())")
        try data.write(to: temp, options: .atomic)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else {
                throw LocusError("cannot write \(destination.lastPathComponent): a directory is in the way at \(destination.path)")
            }
            do {
                _ = try fm.replaceItemAt(destination, withItemAt: temp)
            } catch {
                throw LocusError("failed to replace \(destination.lastPathComponent): \(error.localizedDescription)")
            }
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
    }

    // MARK: - Read

    /// Load a complete map. Every file a crawl writes must be present and the
    /// index must agree with the arrays — a partial or torn map used to load
    /// as empty arrays and answer queries as if nothing was referenced.
    public static func load(from directory: URL) throws -> (map: LocusMap, index: Index) {
        let fm = FileManager.default
        for file in [elementsFile, testsFile, orphansFile, missingFile, indexFile] {
            guard fm.fileExists(atPath: directory.appendingPathComponent(file).path) else {
                throw LocusError("map at \(directory.path) is incomplete: \(file) is missing. Run `locus crawl <sourceRoot>` again.")
            }
        }
        let elements = try read([ElementRecord].self, directory.appendingPathComponent(elementsFile)) ?? []
        let tests = try read([ElementTests].self, directory.appendingPathComponent(testsFile)) ?? []
        let orphans = try read([OrphanLiteral].self, directory.appendingPathComponent(orphansFile)) ?? []
        let missing = try read([MissingIdentifier].self, directory.appendingPathComponent(missingFile)) ?? []
        let index = try read(Index.self, directory.appendingPathComponent(indexFile)) ?? Index(
            version: MapFormat.version, tool: MapFormat.tool, sourceRoot: directory.path,
            testGlobs: [], excludes: [], counts: [:]
        )
        guard index.version == MapFormat.version else {
            throw LocusError(
                "map at \(directory.path) was written by format version \(index.version); this locus reads \(MapFormat.version). Run `locus crawl <sourceRoot>` again."
            )
        }
        // Generation consistency: the index counts what one complete crawl
        // wrote. A mismatch means two crawls interleaved (or a hand edit) —
        // answering from mixed generations is the silent-wrong-answer failure
        // this validation exists to prevent.
        let actual: [String: Int] = [
            "elements": elements.count,
            "identifiedTests": tests.count,
            "orphanLiterals": orphans.count,
            "missingIdentifiers": missing.count,
        ]
        for (key, found) in actual {
            if let expected = index.counts[key], expected != found {
                throw LocusError(
                    "map at \(directory.path) is inconsistent: index says \(expected) \(key), files carry \(found). Run `locus crawl <sourceRoot>` again."
                )
            }
        }
        let map = LocusMap(
            sourceRoot: index.sourceRoot,
            elements: elements, tests: tests, orphans: orphans, missingIdentifiers: missing
        )
        return (map, index)
    }

    /// Resolve the map directory the same way the CLI does: explicit `--out`
    /// wins, otherwise `.locus` relative to the working directory.
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
