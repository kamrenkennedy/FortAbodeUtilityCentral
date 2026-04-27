import Foundation

// MARK: - Run Result

/// Outcome of a single engine run. Carries enough state for the UI to surface
/// success/failure pills, last-run timestamps, and a tail-of-stdout/stderr for
/// the diagnostic detail sheet without retaining the full transcript.
public struct RunResult: Sendable, Equatable {
    public let succeeded: Bool
    public let durationSeconds: Double
    public let summary: String
    public let stdoutTail: String
    public let stderrTail: String
    public let finishedAt: Date

    public init(
        succeeded: Bool,
        durationSeconds: Double,
        summary: String,
        stdoutTail: String,
        stderrTail: String,
        finishedAt: Date
    ) {
        self.succeeded = succeeded
        self.durationSeconds = durationSeconds
        self.summary = summary
        self.stdoutTail = stdoutTail
        self.stderrTail = stderrTail
        self.finishedAt = finishedAt
    }
}

// MARK: - Progress Stream

/// Line-buffered progress token. The store consumes these as `runState`
/// transitions ("Starting…" → "Running step 4 of 12: Gmail pull" → done).
public enum RunProgress: Sendable {
    case stdoutLine(String)
    case stderrLine(String)
}

// MARK: - Engine Runner

/// Spawns the `claude` CLI and runs the Weekly Rhythm Engine skill. Modeled
/// after the `Process` pattern in `BackgroundTaskService.loadLaunchAgent` —
/// no shell, explicit executable URL, captured stdout/stderr.
///
/// Open question (intentional): the exact CLI invocation. v4.3.0 ships with
/// `claude --print "Run my Weekly Rhythm Engine"` which relies on the skill's
/// own description-match triggering inside the CLI. If a future CLI build
/// requires explicit `--skill weekly-rhythm-engine` or similar, swap the
/// `arguments` literal below; the rest of the runner stays the same.
public actor WeeklyRhythmEngineRunner {

    /// Default timeout — engine runs typically complete in 30-90 seconds; 5
    /// minutes leaves headroom for slow GCal/Gmail pulls without hanging the
    /// app forever on a stuck process.
    public static let defaultTimeoutSeconds: Double = 300

    private let timeoutSeconds: Double

    public init(timeoutSeconds: Double = WeeklyRhythmEngineRunner.defaultTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Run the engine and return a `RunResult`. The optional `onProgress`
    /// callback is invoked for each captured stdout/stderr line so the store
    /// can surface live progress on the run pill.
    public func run(
        cliPath: String,
        onProgress: (@Sendable (RunProgress) -> Void)? = nil
    ) async -> RunResult {
        let startedAt = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "--print",
            "Run my Weekly Rhythm Engine"
        ]

        // Inherit a sensible PATH. Sparkle-launched processes get launchd's
        // skinny PATH otherwise, which means subprocesses spawned by `claude`
        // (rg, git, mcp servers) wouldn't find their dependencies.
        var environment = ProcessInfo.processInfo.environment
        if let existing = environment["PATH"] {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existing)"
        } else {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Live readers stream lines into our tail buffers and (optionally) the
        // progress callback. `readabilityHandler` runs on a background queue —
        // we serialize buffer mutations through a dedicated dispatch queue to
        // avoid Sendable warnings on shared state.
        let buffer = LineBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                let str = String(line)
                buffer.appendStdout(str)
                onProgress?(.stdoutLine(str))
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                let str = String(line)
                buffer.appendStderr(str)
                onProgress?(.stderrLine(str))
            }
        }

        await ErrorLogger.shared.log(
            area: "WeeklyRhythmEngine.Runner.start",
            message: "Spawning Claude CLI",
            context: ["cliPath": cliPath, "timeoutSeconds": "\(timeoutSeconds)"]
        )

        do {
            try process.run()
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythmEngine.Runner.spawnFailed",
                message: "Failed to spawn Claude CLI",
                context: ["cliPath": cliPath, "error": "\(error)"]
            )
            return RunResult(
                succeeded: false,
                durationSeconds: 0,
                summary: "Could not start Claude CLI: \(error.localizedDescription)",
                stdoutTail: "",
                stderrTail: "",
                finishedAt: Date()
            )
        }

        // Race process completion against the timeout. Whichever finishes first
        // wins; the loser is cancelled.
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Self.waitForExit(process: process)
                return false
            }
            group.addTask { [timeoutSeconds] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return true
            }
            // First child to return tells us whether the process exited or the
            // timeout fired. Cancel siblings either way.
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }

        if timedOut, process.isRunning {
            process.terminate()
        }

        // Drain readers — readabilityHandler closures may still be in flight
        // when the process exits. Setting handler to nil flushes safely.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startedAt)
        let stdoutTail = buffer.stdoutTail()
        let stderrTail = buffer.stderrTail()
        let succeeded = !timedOut && exitCode == 0

        let summary: String
        if timedOut {
            summary = "Engine run timed out after \(Int(timeoutSeconds))s. The CLI was terminated."
        } else if succeeded {
            // Last non-empty stdout line is usually the engine's own success
            // message ("Dashboard rendered. 5 mutations applied."). Fall back
            // to a generic note if stdout is empty.
            summary = stdoutTail.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init)
                ?? "Engine run completed."
        } else {
            let firstError = stderrTail.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init)
            summary = firstError ?? "Engine run failed (exit code \(exitCode))."
        }

        await ErrorLogger.shared.log(
            area: "WeeklyRhythmEngine.Runner.finished",
            message: succeeded ? "Engine run succeeded" : "Engine run failed",
            context: [
                "succeeded": "\(succeeded)",
                "exitCode": "\(exitCode)",
                "timedOut": "\(timedOut)",
                "durationSeconds": String(format: "%.1f", duration)
            ]
        )

        return RunResult(
            succeeded: succeeded,
            durationSeconds: duration,
            summary: summary,
            stdoutTail: stdoutTail,
            stderrTail: stderrTail,
            finishedAt: Date()
        )
    }

    /// Park a continuation until the process exits. `Process.waitUntilExit()`
    /// is blocking, so we hop to a detached thread.
    private static func waitForExit(process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }
}

// MARK: - Line Buffer
//
// Tail-only buffer for stdout/stderr. We don't need the full transcript —
// only enough to surface a meaningful summary on success and a useful first
// error line on failure. `linesPerStream = 200` is generous for diagnostics
// without ballooning memory on a long run.

private final class LineBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.WeeklyRhythmEngine.LineBuffer")
    private var stdout: [String] = []
    private var stderr: [String] = []
    private let linesPerStream = 200

    func appendStdout(_ line: String) {
        queue.sync {
            stdout.append(line)
            if stdout.count > linesPerStream {
                stdout.removeFirst(stdout.count - linesPerStream)
            }
        }
    }

    func appendStderr(_ line: String) {
        queue.sync {
            stderr.append(line)
            if stderr.count > linesPerStream {
                stderr.removeFirst(stderr.count - linesPerStream)
            }
        }
    }

    func stdoutTail() -> String {
        queue.sync { stdout.joined(separator: "\n") }
    }

    func stderrTail() -> String {
        queue.sync { stderr.joined(separator: "\n") }
    }
}
