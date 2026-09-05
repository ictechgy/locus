import Foundation

/// Git integration through `Process`. locus never mutates repository
/// state; it only reads diffs and status.
public enum GitDiff {
    public struct Result {
        public var files: [String]
        public var repositoryRoot: String
    }

    /// Changed files relative to the repository root.
    /// - When `ref` is given: `git diff --name-only <ref>` (ref..worktree).
    /// - Otherwise: `git diff --name-only HEAD` (staged + unstaged). Falls back
    ///   to `git diff --name-only` when the repository has no commits yet.
    ///   Untracked files are not reported (v0.1 limitation, documented).
    public static func changedFiles(workingDirectory: URL, ref: String?) throws -> Result {
        if let ref {
            // A ref is data, never a git option: leading "-" could turn it into
            // e.g. `--output=<path>` (argument injection into git).
            guard !ref.hasPrefix("-") else {
                throw LocusError("invalid git ref '\(ref)': must not start with '-'.")
            }
        }
        let candidates: [[String]] = ref != nil
            ? [["diff", "--name-only", "--end-of-options", ref!]]
            : [["diff", "--name-only", "HEAD"], ["diff", "--name-only"]]

        var lastError: String?
        for arguments in candidates {
            let (exit, stdout, stderr) = run(arguments: arguments, workingDirectory: workingDirectory)
            if exit == 0 {
                let files = stdout.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let root = repoTopLevel(workingDirectory: workingDirectory) ?? workingDirectory.path
                return Result(files: files.sorted(), repositoryRoot: root)
            }
            lastError = stderr.isEmpty ? stdout : stderr
        }
        throw LocusError("git diff failed: \(lastError ?? "unknown error"). Is \(workingDirectory.path) inside a git repository?")
    }

    /// `git rev-parse --show-toplevel`, nil when not a repository.
    public static func repoTopLevel(workingDirectory: URL) -> String? {
        let (exit, stdout, _) = run(arguments: ["rev-parse", "--show-toplevel"], workingDirectory: workingDirectory)
        guard exit == 0 else { return nil }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run a git command, capturing stdout/stderr. Both pipes are drained
    /// concurrently — reading stdout to EOF while git fills the 64KB stderr
    /// pipe would deadlock a sequential drain.
    ///
    /// Uses /usr/bin/git when present: MCP clients launched from GUI apps pass
    /// a minimal PATH where `env git` lookup can fail even though git exists.
    public static func run(arguments: [String], workingDirectory: URL) -> (exit: Int32, stdout: String, stderr: String) {
        let process = Process()
        if FileManager.default.fileExists(atPath: "/usr/bin/git") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
        }
        process.currentDirectoryURL = workingDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return (-1, "", "failed to launch git: \(error.localizedDescription)")
        }
        let group = DispatchGroup()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    /// Decide whether an element's file (relative to the crawled source root)
    /// is touched by a changed file (relative to the repo root). Matches by
    /// equality or by suffix in either direction, since sourceRoot may be a
    /// subdirectory of the repository.
    public static func touches(elementFile: String, changedFile: String) -> Bool {
        if elementFile == changedFile { return true }
        return changedFile.hasSuffix("/" + elementFile) || elementFile.hasSuffix("/" + changedFile)
    }
}
