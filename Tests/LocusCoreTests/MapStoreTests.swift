import XCTest
@testable import LocusCore

/// Map loading and writing: a partial or torn map must be rejected loudly —
/// it used to load as empty arrays and answer queries as if nothing was
/// referenced (affected-tests reporting 0 tests, exit 0).
final class MapStoreTests: XCTestCase {
    private var root: URL!
    private var mapDir: URL!
    private var map: LocusMap!
    private var index: MapStore.Index!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = Fixture.makeTree("mapstore", files: [:])
        mapDir = root.appendingPathComponent("map", isDirectory: true)
        map = LocusMap(
            sourceRoot: root.path,
            elements: [
                ElementRecord(identifier: "a.b", kind: "Button", file: "A.swift", line: 1, column: 1, symbol: "A.body"),
            ],
            tests: [
                ElementTests(identifier: "a.b", tests: [TestReference(file: "T.swift", line: 2, column: 3)]),
            ],
            orphans: [], missingIdentifiers: []
        )
        index = MapStore.Index(
            version: MapFormat.version, tool: MapFormat.tool, sourceRoot: root.path,
            testGlobs: ["*Tests*"], excludes: [],
            counts: [
                "elements": 1, "identifiedTests": 1,
                "orphanLiterals": 0, "missingIdentifiers": 0,
            ]
        )
        try MapStore.write(map, index: index, to: mapDir)
    }

    override func tearDownWithError() throws {
        Fixture.cleanup(root)
        try super.tearDownWithError()
    }

    func testCompleteMapLoads() throws {
        let (loaded, loadedIndex) = try MapStore.load(from: mapDir)
        XCTAssertEqual(loaded.elements, map.elements)
        XCTAssertEqual(loaded.tests, map.tests)
        XCTAssertEqual(loadedIndex.counts["elements"], 1)
    }

    func testMissingDataFileIsRejected() throws {
        try FileManager.default.removeItem(at: mapDir.appendingPathComponent(MapStore.testsFile))
        XCTAssertThrowsError(try MapStore.load(from: mapDir)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("incomplete"), message)
            XCTAssertTrue(message.contains(MapStore.testsFile), message)
        }
    }

    func testMissingIndexIsRejected() throws {
        try FileManager.default.removeItem(at: mapDir.appendingPathComponent(MapStore.indexFile))
        XCTAssertThrowsError(try MapStore.load(from: mapDir)) { error in
            XCTAssertTrue("\(error)".contains(MapStore.indexFile), "\(error)")
        }
    }

    func testWrongFormatVersionIsRejected() throws {
        let stale = MapStore.Index(
            version: 99, tool: index.tool, sourceRoot: index.sourceRoot,
            testGlobs: index.testGlobs, excludes: index.excludes, counts: index.counts
        )
        try MapStore.write(map, index: stale, to: mapDir)
        XCTAssertThrowsError(try MapStore.load(from: mapDir)) { error in
            XCTAssertTrue("\(error)".contains("format version"), "\(error)")
        }
    }

    func testGenerationMismatchIsRejected() throws {
        // A torn write across two crawls: the index counts a different
        // generation than the files carry.
        let torn = MapStore.Index(
            version: MapFormat.version, tool: index.tool, sourceRoot: index.sourceRoot,
            testGlobs: index.testGlobs, excludes: index.excludes,
            counts: [
                "elements": 7, "identifiedTests": 1,
                "orphanLiterals": 0, "missingIdentifiers": 0,
            ]
        )
        try MapStore.write(map, index: torn, to: mapDir)
        XCTAssertThrowsError(try MapStore.load(from: mapDir)) { error in
            XCTAssertTrue("\(error)".contains("inconsistent"), "\(error)")
        }
    }

    func testWriteFailsWhenADirectoryOccupiesTheDestination() throws {
        // `mkdir map/elements.json` used to make the atomic replace fail
        // silently — the crawl reported success and the map was never written.
        let destination = mapDir.appendingPathComponent(MapStore.elementsFile)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertThrowsError(try MapStore.write(map, index: index, to: mapDir)) { error in
            XCTAssertTrue("\(error)".contains("directory is in the way"), "\(error)")
        }
    }
}
