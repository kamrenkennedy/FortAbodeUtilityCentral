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
/// transitions ("Starting…" → "Using Gmail" → "Using Memory" → done).
public enum RunProgress: Sendable {
    case stdoutLine(String)
    case stderrLine(String)
}

// MARK: - Engine Runner
//
// Spawns the `claude` CLI and runs the Weekly Rhythm Engine skill. Phase 6.1:
// uses `--output-format stream-json --include-partial-messages` so each line
// of stdout is a discrete JSON event with a `type` discriminator. We extract
// tool-use breadcrumbs ("Using Gmail…") for the run pill and capture the
// final `result` event verbatim for the post-run summary. Without stream-json
// the CLI buffers the entire response until exit, which makes the pill go
// silent for 60-90 seconds.

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
    /// callback is invoked for each parsed event so the store can surface live
    /// progress on the run pill.
    public func run(
        cliPath: String,
        onProgress: (@Sendable (RunProgress) -> Void)? = nil
    ) async -> RunResult {
        let startedAt = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--include-partial-messages",
            // `claude --print` requires --verbose with stream-json (per the
            // CLI's own validation; without it the CLI errors out).
            "--verbose",
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

        // Live readers stream lines into our tail buffer + JSON parser. The
        // splitter handles partial chunks (data may arrive mid-line); the
        // parser turns each complete line into RunProgress tokens and tracks
        // the final `result` event for post-run summary.
        let buffer = LineBuffer()
        let stdoutSplitter = LineSplitter()
        let stderrSplitter = LineSplitter()
        let parser = StreamEventParser()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in stdoutSplitter.append(chunk) {
                buffer.appendStdout(line)
                for token in parser.parse(line: line) {
                    onProgress?(token)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in stderrSplitter.append(chunk) {
                buffer.appendStderr(line)
                onProgress?(.stderrLine(line))
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

        // Flush trailing partial lines (no newline at EOF).
        for line in stdoutSplitter.flush() {
            buffer.appendStdout(line)
            for token in parser.parse(line: line) {
                onProgress?(token)
            }
        }
        for line in stderrSplitter.flush() {
            buffer.appendStderr(line)
        }

        let exitCode = process.terminationStatus
        let duration = Date().timeIntervalSince(startedAt)
        let stdoutTail = buffer.stdoutTail()
        let stderrTail = buffer.stderrTail()

        // Success: process exited cleanly AND the engine itself reported
        // is_error=false in its final result event. A 0 exit with is_error=true
        // means the CLI ran but the engine encountered an error mid-run.
        let resultEvent = parser.lastResultEvent()
        let engineReportedError = resultEvent?.isError == true
        let succeeded = !timedOut && exitCode == 0 && !engineReportedError

        let summary: String
        if timedOut {
            summary = "Engine run timed out after \(Int(timeoutSeconds))s. The CLI was terminated."
        } else if let resultText = resultEvent?.result, !resultText.trimmingCharacters(in: .whitespaces).isEmpty {
            // The engine's own final-result string. This is the canonical
            // human-readable summary — preserved verbatim regardless of
            // success/failure.
            summary = resultText
        } else if succeeded {
            summary = "Engine run completed."
        } else {
            // No structured result event — fall back to the first stderr line
            // (often where the CLI itself prints its complaint).
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
                "engineReportedError": "\(engineReportedError)",
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

// MARK: - Line Splitter
//
// Buffers partial chunks across `readabilityHandler` invocations and emits
// only complete lines. Critical for stream-json parsing — JSON events are
// newline-delimited, and a chunk boundary mid-event would break decoding.

private final class LineSplitter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.WeeklyRhythmEngine.LineSplitter")
    private var pending: String = ""

    /// Append a chunk and return any complete lines (without the trailing
    /// newline). Any trailing partial line stays buffered until the next call.
    func append(_ chunk: String) -> [String] {
        queue.sync {
            pending += chunk
            var lines: [String] = []
            while let range = pending.range(of: "\n") {
                let line = String(pending[..<range.lowerBound])
                lines.append(line)
                pending = String(pending[range.upperBound...])
            }
            return lines
        }
    }

    /// Drain any remaining pending content. Call once after the process exits
    /// to capture a trailing line that wasn't newline-terminated.
    func flush() -> [String] {
        queue.sync {
            guard !pending.isEmpty else { return [] }
            let result = [pending]
            pending = ""
            return result
        }
    }
}

// MARK: - Stream Event Parser
//
// Decodes one JSON event per line. For each `assistant` event with tool_use
// content blocks, emits a "Using <tool>" progress token. The final `result`
// event is captured verbatim for the post-run summary; everything else
// (system, user, mid-stream text deltas) is silently dropped.

private final class StreamEventParser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.WeeklyRhythmEngine.StreamEventParser")
    private var lastResult: ResultEvent?
    private var lastToolName: String?

    struct ResultEvent: Sendable {
        let isError: Bool
        let result: String
    }

    /// Parse a single line and return any RunProgress tokens it produced.
    /// Returns an empty array for unparseable / uninteresting events.
    func parse(line: String) -> [RunProgress] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
            return []
        }

        switch event.type {
        case "assistant":
            return toolUseProgress(from: event)
        case "result":
            queue.sync {
                lastResult = ResultEvent(
                    isError: event.isError ?? false,
                    result: event.result ?? ""
                )
            }
            return []
        default:
            return []
        }
    }

    /// Return the most recent `result` event, if any. Called once at the end
    /// of the run to extract the engine's final summary string.
    func lastResultEvent() -> ResultEvent? {
        queue.sync { lastResult }
    }

    private func toolUseProgress(from event: StreamEvent) -> [RunProgress] {
        guard let blocks = event.message?.content else { return [] }
        var tokens: [RunProgress] = []
        for block in blocks {
            guard case .toolUse(let name) = block else { continue }
            // Dedupe consecutive identical tool names — partial-message events
            // can re-emit the same tool_use as it streams in.
            let shouldEmit = queue.sync { () -> Bool in
                guard lastToolName != name else { return false }
                lastToolName = name
                return true
            }
            if shouldEmit {
                tokens.append(.stdoutLine("Using \(humanize(toolName: name))"))
            }
        }
        return tokens
    }

    /// Map raw tool names to human-readable labels for the run pill. Falls
    /// back to the raw name (with underscores → spaces) for unknown tools so
    /// the user still sees something meaningful.
    private func humanize(toolName: String) -> String {
        switch toolName {
        case "mcp__gmail":                          return "Gmail"
        case "mcp__google-calendar":                return "Google Calendar"
        case "mcp__apple-reminders":                return "Apple Reminders"
        case "mcp__memory", "mcp__kam-memory":      return "Memory"
        case "mcp__notion", "mcp__notion-tiera":    return "Notion"
        case "Read":                                return "Reading file"
        case "Write":                               return "Writing file"
        case "Edit":                                return "Editing file"
        case "Bash":                                return "Running command"
        default:
            return toolName.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Stream Event JSON shapes
//
// Mirrors the `claude --print --output-format stream-json` event grammar.
// Decoder is permissive — every field is optional except `type` so a future
// CLI version that adds new event kinds doesn't break parsing.

private struct StreamEvent: Decodable {
    let type: String
    let isError: Bool?
    let result: String?
    let message: Message?

    private enum CodingKeys: String, CodingKey {
        case type, message, result
        case isError = "is_error"
    }

    struct Message: Decodable {
        let content: [ContentBlock]?
    }

    enum ContentBlock: Decodable {
        case text(String)
        case toolUse(name: String)
        case other

        private enum CodingKeys: String, CodingKey {
            case type, text, name
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let blockType = (try? c.decode(String.self, forKey: .type)) ?? ""
            switch blockType {
            case "text":
                let text = (try? c.decode(String.self, forKey: .text)) ?? ""
                self = .text(text)
            case "tool_use":
                let name = (try? c.decode(String.self, forKey: .name)) ?? "tool"
                self = .toolUse(name: name)
            default:
                self = .other
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
