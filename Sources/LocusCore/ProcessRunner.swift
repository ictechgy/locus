import Foundation

/// Spawns a subprocess with concurrent pipe drain and a hard timeout.
/// Shared by the git and idb integrations so a wedged child can never hang
/// a CLI query or the MCP loop.
enum ProcessRunner {
    struct Outcome {
        var exit: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    /// - Parameters:
    ///   - executableURL: binary to launch (resolve PATH yourself — see
    ///     GitDiff for the /usr/bin preference rationale).
    ///   - timeout: seconds to wait for the child to finish and drain its
    ///     pipes. On expiry the child gets SIGTERM (SIGKILL is not exposed
    ///     by Process); a child that ignores SIGTERM leaks its drain
    ///     threads, but the caller is unblocked either way — that is the
    ///     contract.
    static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        timeout: TimeInterval
    ) -> Outcome {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return Outcome(
                exit: -1, stdout: "",
                stderr: "failed to launch \(executableURL.lastPathComponent): \(error.localizedDescription)",
                timedOut: false
            )
        }
        // Drain both pipes concurrently: reading one to EOF while the child
        // fills the other's 64KB buffer would deadlock a sequential drain.
        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global().async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return Outcome(exit: -1, stdout: "", stderr: "timed out after \(timeout)s", timedOut: true)
        }
        process.waitUntilExit()
        return Outcome(
            exit: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            timedOut: false
        )
    }
}
