import Foundation
import LocusCore

let version = MapFormat.releaseVersion

let helpText = """
locus \(version) — a map between UI elements and source for agents.

USAGE:
    locus crawl <sourceRoot> [--tests-glob G]... [--exclude P]... [--out DIR]
    locus where-is <identifier> [--out DIR]
    locus what-renders <symbol|file> [--out DIR]
    locus affected-tests [--ref <git-ref>] [--files f1,f2] [--out DIR]
    locus missing-identifiers [--out DIR]
    locus snapshot <dump.json|-> [--udid UDID] [--out DIR]
    locus mcp [--out DIR]
    locus --help | --version

COMMANDS:
    crawl                  Build the static map: SwiftSyntax pass over *.swift
                           under sourceRoot + reverse index of test literals.
                           Writes elements.json, tests.json, orphans.json,
                           missing-identifiers.json, index.json atomically.
        --tests-glob G     glob(s) deciding test/automation files (default *Tests*)
        --exclude P        path glob(s) to skip while crawling
        --out DIR          map directory (default ./.locus)
    where-is               Element(s) with the given accessibility identifier
                           plus the tests that reference it.
    what-renders           Elements anchored in a symbol (Type, Type.member)
                           or a file.
    affected-tests         Changed files (git diff, or --files) -> elements ->
                           deduplicated test list.
        --ref R            diff against a git ref (default: working tree)
        --files f1,f2      explicit changed files; overrides git diff
    missing-identifiers    Interactive-looking controls without an
                           accessibilityIdentifier, per file.
    mcp                    Serve the map as a stdio MCP server (JSON-RPC 2.0)
                           with tools: where_is, what_renders, affected_tests,
                           missing_identifiers, match_snapshot. Exits 0 on EOF.
    snapshot               Match a runtime accessibility-tree dump (JSON)
                           against the map: identifier direct-match (high),
                           label heuristic (medium/low), residual report.
        <dump.json> | -    dump file, or - to read the dump from stdin
        --udid UDID        capture the dump via `idb ui describe-all` instead
        --out DIR          map directory (default ./.locus)

DEFAULTS:
    Map lives in ./.locus. Run crawl once, then query from the same
    working directory (or pass --out).
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("locus: error: \(message)\n".utf8))
    exit(2)
}

/// Parse with a command grammar, or exit with the usage error.
func parseOrDie(_ arguments: [String], grammar: CommandGrammar) -> ParsedArgs {
    do {
        return try parse(arguments, grammar: grammar)
    } catch {
        fail("\(error)")
    }
}

func run(_ arguments: [String]) -> Int32 {
    guard let command = arguments.first else {
        print(helpText)
        return 0
    }
    let rest = Array(arguments.dropFirst())

    switch command {
    case "--help", "-h", "help":
        print(helpText)
        return 0
    case "--version", "-v", "version":
        print("locus \(version)")
        return 0
    case "crawl":
        return runCrawl(rest)
    case "where-is":
        return runWhereIs(rest)
    case "what-renders":
        return runWhatRenders(rest)
    case "affected-tests":
        return runAffectedTests(rest)
    case "missing-identifiers":
        return runMissingIdentifiers(rest)
    case "snapshot":
        return runSnapshot(rest)
    case "mcp":
        return runMCP(rest)
    default:
        fail("unknown command '\(command)'. Try --help.")
    }
}

// MARK: - crawl

func runCrawl(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(
        positional: 1...1, valueOptions: ["out"], repeatableOptions: ["tests-glob", "exclude"]
    ))
    let sourceRoot = URL(fileURLWithPath: args.positional[0], isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        fail("sourceRoot '\(sourceRoot.path)' is not a directory.")
    }
    let testGlobs = args.values("tests-glob").isEmpty ? ["*Tests*"] : args.values("tests-glob")
    let excludes = args.values("exclude")
    let mapDirectory = MapStore.resolveDirectory(explicit: args.value("out"))

    do {
        let crawler = Crawler()
        let (elements, missing, constants) = try crawler.crawl(root: sourceRoot, excludes: excludes)
        let knownIdentifiers = Set(elements.map(\.identifier))
        let scanner = TestScanner()
        let (tests, orphans) = try scanner.scan(
            root: sourceRoot, globs: testGlobs, excludes: excludes,
            knownIdentifiers: knownIdentifiers, constants: constants
        )
        let map = LocusMap(
            sourceRoot: sourceRoot.path,
            elements: elements, tests: tests, orphans: orphans, missingIdentifiers: missing
        )
        let index = MapStore.Index(
            version: MapFormat.version, tool: MapFormat.tool,
            sourceRoot: sourceRoot.path, testGlobs: testGlobs, excludes: excludes,
            counts: [
                "elements": elements.count,
                "identifiedTests": tests.count,
                "orphanLiterals": orphans.count,
                "missingIdentifiers": missing.count,
            ]
        )
        try MapStore.write(map, index: index, to: mapDirectory)
        print("crawled \(sourceRoot.path)")
        print("  elements:              \(elements.count)")
        print("  identifiers in tests:  \(tests.count)")
        print("  orphan literals:       \(orphans.count)")
        print("  missing identifiers:   \(missing.count)")
        print("  map:                   \(mapDirectory.path)")
        return 0
    } catch {
        fail("\(error)")
    }
}

// MARK: - queries

func runWhereIs(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 1...1, valueOptions: ["out"]))
    let identifier = args.positional[0]
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let result = try engine.whereIs(identifier)
        print(result.locusJSON())
        return 0
    } catch {
        fail("\(error)")
    }
}

func runWhatRenders(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 1...1, valueOptions: ["out"]))
    let target = args.positional[0]
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let result = try engine.whatRenders(target)
        print(result.locusJSON())
        return 0
    } catch {
        fail("\(error)")
    }
}

func runAffectedTests(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 0...0, valueOptions: ["out", "ref", "files"]))
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let files = args.value("files")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let result = try engine.affectedTests(ref: args.value("ref"), files: files)
        print(result.locusJSON())
        return 0
    } catch {
        fail("\(error)")
    }
}

func runMissingIdentifiers(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 0...0, valueOptions: ["out"]))
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let result = engine.missingIdentifiers()
        print(result.locusJSON())
        return 0
    } catch {
        fail("\(error)")
    }
}

// MARK: - snapshot

func runSnapshot(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 0...1, valueOptions: ["out", "udid"]))
    let dumpText: String
    if let udid = args.value("udid") {
        do {
            dumpText = try SnapshotCapture.idbDescribeAll(udid: udid)
        } catch {
            fail("\(error)")
        }
    } else if let path = args.positional.first {
        if path == "-" {
            dumpText = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        } else {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                fail("cannot read snapshot dump at '\(path)'.")
            }
            dumpText = text
        }
    } else {
        fail("snapshot requires a <dump.json> path, '-' for stdin, or --udid <udid>.")
    }
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let report = try engine.matchSnapshot(dump: dumpText)
        print(report.locusJSON())
        return 0
    } catch {
        fail("\(error)")
    }
}

// MARK: - mcp

func runMCP(_ arguments: [String]) -> Int32 {
    let args = parseOrDie(arguments, grammar: CommandGrammar(positional: 0...0, valueOptions: ["out"]))
    do {
        let engine = try Engine.load(mapDirectory: args.value("out"), workingDirectory: currentDirectory())
        let mcp = MCPEngine(engine: engine)
        return MCPStdio.run(engine: mcp)
    } catch {
        fail("\(error)")
    }
}

func currentDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

// Entry point: main.swift calls run with command-line arguments.
exit(run(Array(CommandLine.arguments.dropFirst())))
