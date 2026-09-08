import Foundation

/// One node of a runtime accessibility-tree dump (simulator or device).
/// Field names are normalized from the dumping tool's vocabulary at parse
/// time — see `SnapshotDump.parse`.
public struct SnapshotNode: Codable, Equatable {
    /// Runtime accessibility identifier, when the element has one.
    public var identifier: String?
    public var label: String?
    public var kind: String?
    /// Position in the dump (0-based); keeps reports stable in dump order.
    public var index: Int

    public init(identifier: String?, label: String?, kind: String?, index: Int) {
        self.identifier = identifier
        self.label = label
        self.kind = kind
        self.index = index
    }
}

/// Parses accessibility-tree dumps. Two accepted envelope shapes:
/// a bare JSON array of element objects, or an object with an `elements`
/// array. Element field names are matched permissively across tool
/// vocabularies (XCUITest-style, idb `AX…`-style), since agents will hand
/// locus dumps from whatever tool they drove the simulator with:
///
/// - identifier ← `identifier` | `AXIdentifier` | `AXUniqueId` |
///   `accessibilityIdentifier` (string values only)
/// - label ← `label` | `AXLabel` | `accessibilityLabel` | `text`
/// - kind ← `kind` | `type` | `elementType` | `AXType` | `role`
public enum SnapshotDump {
    public static func parse(_ text: String) throws -> [SnapshotNode] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw LocusError("snapshot is not valid JSON.")
        }
        let rawElements: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rawElements = array
        } else if let object = json as? [String: Any],
                  let nested = (object["elements"] ?? object["tree"]) as? [[String: Any]] {
            rawElements = nested
        } else {
            throw LocusError("snapshot must be a JSON array of elements, or an object with an `elements` array.")
        }
        return rawElements.enumerated().map { index, fields in
            SnapshotNode(
                identifier: firstString(fields, ["identifier", "AXIdentifier", "AXUniqueId", "accessibilityIdentifier"]),
                label: firstString(fields, ["label", "AXLabel", "accessibilityLabel", "text"]),
                kind: firstString(fields, ["kind", "type", "elementType", "AXType", "role"]),
                index: index
            )
        }
    }

    private static func firstString(_ fields: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

/// Read-only `idb ui describe-all` integration (prototype dump source).
/// idb is optional: when absent the error says so, and file/stdin dumps keep
/// working — locus itself never depends on any external tool beyond git.
/// Unlike git there is no stable /usr/bin path for idb, so PATH lookup via
/// `/usr/bin/env` is the only portable route.
public enum SnapshotCapture {
    /// idb against a slow simulator can take a while — still bounded, so a
    /// wedged companion never hangs the CLI.
    public static let idbTimeout: TimeInterval = 120

    public static func idbDescribeAll(udid: String) throws -> String {
        guard !udid.isEmpty else {
            throw LocusError("--udid must not be empty.")
        }
        // Same rule as git refs in GitDiff: a value is data, never a tool
        // option — a leading "-" could turn into an idb flag.
        guard !udid.hasPrefix("-") else {
            throw LocusError("invalid udid '\(udid)': must not start with '-'.")
        }
        let outcome = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["idb", "ui", "describe-all", "--udid", udid],
            timeout: idbTimeout
        )
        if outcome.timedOut {
            throw LocusError("idb describe-all timed out after \(Int(idbTimeout))s.")
        }
        guard outcome.exit == 0 else {
            let message = outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocusError("idb describe-all failed: \(message.isEmpty ? "exit \(outcome.exit)" : message)")
        }
        return outcome.stdout
    }
}

/// Matches a runtime dump against the static ledger.
///
/// Matching order is the product principle: deterministic identifier
/// direct-match first (confidence `high`), then a label heuristic for
/// identifier-less nodes — unique label match is `medium`, `low` when the
/// kinds disagree. Nothing is ever asserted: residuals are reported, not
/// hidden, and identifier-less on-screen nodes are the automation-debt
/// metric from the design doc.
public struct SnapshotMatcher {
    public init() {}

    public struct Match: Codable, Equatable {
        /// The node's own identifier, when it had one.
        public var identifier: String?
        public var label: String?
        public var kind: String?
        /// "identifier" | "label" | "none"
        public var matchedBy: String
        /// "high" | "medium" | "low"
        public var confidence: String
        /// Ledger candidates; more than one means the identifier is shared.
        public var elements: [ElementRecord]
    }

    public struct Report: Codable, Equatable {
        public var nodes: Int
        public var matches: [Match]
        /// On-screen nodes without an identifier: visible automation debt.
        public var unidentifiedOnScreen: [SnapshotNode]
        /// On-screen identifiers the ledger does not know (dynamic
        /// identifiers, stale map) — leads, not verdicts.
        public var unmatchedIdentifiers: [String]
        /// Ledger identifiers not seen on this screen (normal: the ledger
        /// spans the whole app). Useful for screen-scoped analysis.
        public var unseenIdentifiers: [String]
        /// Matched nodes (any confidence) / all nodes, rounded to 3 places.
        public var coverage: Double
    }

    public func match(nodes: [SnapshotNode], elements: [ElementRecord]) -> Report {
        // Index the ledger once: per-identifier and per-label buckets, filled
        // in (file, line, column) order so each bucket comes out sorted the
        // way the per-node filters used to sort. Matching drops from
        // O(nodes × elements) to O(nodes + elements) with identical output.
        var identifierBuckets: [String: [ElementRecord]] = [:]
        var labelBuckets: [String: [ElementRecord]] = [:]
        for element in elements.sorted(by: { ($0.file, $0.line, $0.column) < ($1.file, $1.line, $1.column) }) {
            identifierBuckets[element.identifier, default: []].append(element)
            if let label = element.label, !label.isEmpty {
                labelBuckets[label, default: []].append(element)
            }
        }

        var matches: [Match] = []
        var unidentified: [SnapshotNode] = []
        var unmatched: [String] = []

        for node in nodes {
            if let identifier = node.identifier {
                let candidates = identifierBuckets[identifier] ?? []
                matches.append(Match(
                    identifier: identifier,
                    label: node.label,
                    kind: node.kind,
                    matchedBy: candidates.isEmpty ? "none" : "identifier",
                    confidence: candidates.isEmpty ? "low" : "high",
                    elements: candidates
                ))
                if candidates.isEmpty { unmatched.append(identifier) }
                continue
            }
            // No identifier: label heuristic against identified elements.
            let labelCandidates: [ElementRecord]
            if let label = node.label, !label.isEmpty {
                labelCandidates = labelBuckets[label] ?? []
            } else {
                labelCandidates = []
            }
            unidentified.append(node)
            guard labelCandidates.count == 1, let only = labelCandidates.first else {
                matches.append(Match(
                    identifier: nil, label: node.label, kind: node.kind,
                    matchedBy: "none", confidence: "low", elements: []
                ))
                continue
            }
            let kindsAgree = node.kind.map { kind in
                only.kind == "Unknown" || only.kind.caseInsensitiveCompare(kind) == .orderedSame
            } ?? true
            matches.append(Match(
                identifier: nil,
                label: node.label,
                kind: node.kind,
                matchedBy: "label",
                confidence: kindsAgree ? "medium" : "low",
                elements: [only]
            ))
        }

        let seen = Set(nodes.compactMap(\.identifier))
        let unseen = Set(elements.map(\.identifier)).subtracting(seen).sorted()
        let matchedCount = matches.filter { $0.matchedBy != "none" }.count
        let coverage = nodes.isEmpty
            ? 0
            : (Double(matchedCount) / Double(nodes.count) * 1000).rounded() / 1000

        return Report(
            nodes: nodes.count,
            matches: matches,
            unidentifiedOnScreen: unidentified,
            unmatchedIdentifiers: unmatched.sorted(),
            unseenIdentifiers: unseen,
            coverage: coverage
        )
    }
}
