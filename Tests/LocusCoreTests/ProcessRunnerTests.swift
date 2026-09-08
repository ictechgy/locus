import XCTest
@testable import LocusCore

/// Bounded subprocess execution: a wedged child must fail fast instead of
/// hanging the CLI/MCP forever.
final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndExitStatus() {
        let outcome = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"], timeout: 10
        )
        XCTAssertEqual(outcome.exit, 0)
        XCTAssertEqual(outcome.stdout, "hello\n")
        XCTAssertTrue(outcome.stderr.isEmpty)
        XCTAssertFalse(outcome.timedOut)
    }

    func testSleepingExecutableTimesOut() {
        // The "sleeping fake executable": /bin/sleep ignores nobody and
        // holds both pipes open — exactly the wedged-child shape.
        let start = Date()
        let outcome = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"], timeout: 0.5
        )
        XCTAssertTrue(outcome.timedOut)
        XCTAssertTrue(outcome.stderr.contains("timed out"), outcome.stderr)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "timeout must unblock the caller quickly")
    }

    func testLaunchFailureIsReported() {
        let outcome = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/nonexistent/definitely-missing"),
            arguments: [], timeout: 10
        )
        XCTAssertEqual(outcome.exit, -1)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertTrue(outcome.stderr.contains("failed to launch"), outcome.stderr)
    }
}
