import Foundation

// MARK: - Chat Event Stream

/// Typed events emitted by `ClaudeChatTurnRunner` while a single chat turn is
/// in flight. The store consumes these to update the streaming assistant
/// bubble in real time and append tool breadcrumbs.
public enum ClaudeChatEvent: Sendable {
    /// A chunk of assistant text streamed from a `text_delta` event. Append to
    /// the placeholder bubble's content.
    case partialAssistantText(String)

    /// Claude completed a tool call. The runner pairs the `tool_use` from the
    /// assistant message with its matching `tool_result` from the synthetic
    /// user message, then emits this. `succeeded == false` happens when the
    /// CLI is in `--permission-mode default` and the tool was blocked, or when
    /// the tool itself errored.
    case toolUseCompleted(name: String, input: String, succeeded: Bool, output: String?)

    /// Final `result` event arrived with `is_error == false`. `fullText` is
    /// the engine's canonical reply string (mirrors what the deltas already
    /// rendered into the bubble).
    case turnComplete(fullText: String)

    /// Final `result` event arrived with `is_error == true`, OR the process
    /// exited / timed out without any result event at all. Carries a
    /// human-readable reason for surfacing in the bubble.
    case turnFailed(reason: String)

    /// Claude drafted a plan in `--permission-mode plan`. The plan text is
    /// extracted from the Plan tool's `input.plan` field (or ExitPlanMode's
    /// equivalent). Store sets this on the turn and the view renders a Plan
    /// Card with Execute / Cancel instead of a regular bubble.
    case planDrafted(plan: String)

    /// Always the last event for a turn. Carries the CLI's exit code.
    case terminated(exitCode: Int32)
}

// MARK: - Turn Runner
//
// Spawns `claude --print --input-format stream-json ...` per chat turn,
// pipes one user message into stdin, closes stdin to signal end-of-input,
// and streams parsed events back via `onEvent`. This is the per-turn
// re-spawn architecture from Y6 — long-running pipe-mode was rejected
// because `--permission-mode default` silently denies tool calls without
// emitting a permission-request event we could intercept.

public actor ClaudeChatTurnRunner {

    /// 90s default. A typical Q&A turn lands well under 10s; tool-using turns
    /// (Read/Bash/etc.) can stretch toward 30–60s. 90s gives headroom without
    /// hanging the UI on a runaway turn.
    public static let defaultTimeoutSeconds: Double = 90

    private let timeoutSeconds: Double

    public init(timeoutSeconds: Double = ClaudeChatTurnRunner.defaultTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Whether we're starting a fresh server-side session (`--session-id`) or
    /// continuing an existing one (`--resume`). The CLI's `--session-id` flag
    /// only accepts a UUID for a NOT-YET-CREATED session — reusing it on a
    /// follow-up `claude --print` invocation hits an "already in use" guard.
    /// `--resume` is the flag for continuing an existing session.
    public enum SessionMode: Sendable {
        case creating  // first turn — CLI creates the session with this UUID
        case resuming  // every turn after — CLI resumes the existing session
    }

    /// User-pickable Claude model for this turn. Maps to the CLI's `--model`
    /// flag with short aliases (`sonnet` / `opus` / `haiku`); the CLI resolves
    /// each alias to its current latest version, so this stays correct as
    /// Anthropic ships new minor versions without us needing to bump anything.
    public enum ClaudeModel: String, Sendable, Hashable, CaseIterable {
        case sonnet
        case opus
        case haiku
    }

    /// User-facing permission state. The runner maps each case to the right
    /// `--permission-mode` + `--allowedTools` flag combo at spawn time.
    public enum PermissionMode: String, Sendable, Hashable, CaseIterable {
        /// No tools — Claude can think and reply but every tool call is denied.
        /// Maps to `--permission-mode default` with no allowlist.
        case off

        /// Claude can use any tool the user pre-approved in their allowlist.
        /// Maps to `--permission-mode default --allowedTools <list>`.
        case allowlist

        /// Claude drafts a plan first via the built-in Plan tool; no tools
        /// actually execute. The store captures the plan from the assistant
        /// event, the view surfaces it as a Plan Card with Execute / Cancel.
        /// Maps to `--permission-mode plan`.
        case preview

        /// Claude can use any tool. Bypasses every permission check.
        /// Maps to `--permission-mode bypassPermissions`.
        case all
    }

    /// Run a single turn. Spawns the CLI, sends `userMessage`, streams events
    /// via `onEvent`, and returns when the process exits or the timeout fires.
    /// `sessionID` is reused across turns so Claude's server-side context
    /// survives between spawns; `sessionMode` picks the right flag (creating
    /// vs resuming) so we don't double-create.
    public func run(
        cliPath: String,
        sessionID: UUID,
        sessionMode: SessionMode,
        userMessage: String,
        permissionMode: PermissionMode,
        allowedTools: [String],
        model: ClaudeModel,
        timeoutSecondsOverride: Double? = nil,
        onEvent: @Sendable @escaping (ClaudeChatEvent) -> Void
    ) async {
        let effectiveTimeout = timeoutSecondsOverride ?? timeoutSeconds

        // Map UI-facing PermissionMode → actual CLI flags.
        let cliPermissionMode: String
        var allowedToolsFlag: [String] = []
        switch permissionMode {
        case .off:
            cliPermissionMode = "default"
        case .allowlist:
            cliPermissionMode = "default"
            // Empty allowlist in `.allowlist` mode behaves like `.off` — no tools.
            // That's intentional: a user with an empty allowlist gets the same
            // safety as disabling tools entirely.
            if !allowedTools.isEmpty {
                allowedToolsFlag = ["--allowedTools"] + allowedTools
            }
        case .preview:
            cliPermissionMode = "plan"
        case .all:
            cliPermissionMode = "bypassPermissions"
        }

        let sessionFlag: [String]
        switch sessionMode {
        case .creating:
            sessionFlag = ["--session-id", sessionID.uuidString]
        case .resuming:
            sessionFlag = ["--resume", sessionID.uuidString]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--replay-user-messages",
            // `--print` with stream-json requires `--verbose` (CLI validation).
            "--verbose",
            "--model", model.rawValue,
            "--permission-mode", cliPermissionMode
        ] + allowedToolsFlag + sessionFlag

        // Inherit a sensible PATH so MCP server subprocesses spawned by
        // `claude` can find their dependencies (Node, Python, etc.).
        var environment = ProcessInfo.processInfo.environment
        if let existing = environment["PATH"] {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existing)"
        } else {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }

        // Inject the user's Claude OAuth token from Keychain. GUI apps don't
        // inherit shell env vars, so without this every turn 401s.
        if let token = ClaudeAuthKeychainService.readToken() {
            environment["CLAUDE_CODE_OAUTH_TOKEN"] = token
        }

        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutSplitter = LineSplitter()
        let parser = ChatStreamParser()
        let stderrTail = TailBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in stdoutSplitter.append(chunk) {
                for event in parser.parse(line: line) {
                    onEvent(event)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderrTail.append(chunk)
        }

        await ErrorLogger.shared.log(
            area: "ClaudeChat.TurnRunner.start",
            message: "Spawning Claude CLI for chat turn",
            context: [
                "cliPath": cliPath,
                "sessionID": sessionID.uuidString,
                "sessionMode": sessionMode == .creating ? "creating" : "resuming",
                "permissionMode": permissionMode.rawValue,
                "cliPermissionMode": cliPermissionMode,
                "allowedToolsCount": "\(allowedTools.count)",
                "model": model.rawValue
            ]
        )

        do {
            try process.run()
        } catch {
            await ErrorLogger.shared.log(
                area: "ClaudeChat.TurnRunner.spawnFailed",
                message: "Failed to spawn Claude CLI",
                context: ["error": "\(error)"]
            )
            onEvent(.turnFailed(reason: "Could not start Claude CLI: \(error.localizedDescription)"))
            onEvent(.terminated(exitCode: -1))
            return
        }

        // Send one stream-json `user` event then close stdin. Closing is what
        // tells the CLI there are no more user turns coming, so it can finish
        // the current turn and exit.
        let userJSON = Self.makeUserEventJSON(text: userMessage)
        if let data = (userJSON + "\n").data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdinPipe.fileHandleForWriting.close()

        // Race process completion against timeout. Whichever finishes first
        // wins; the loser is cancelled.
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Self.waitForExit(process: process)
                return false
            }
            group.addTask { [effectiveTimeout] in
                try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                return true
            }
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }

        if timedOut, process.isRunning {
            process.terminate()
        }

        // Detach readers — readabilityHandler closures may still be in flight
        // when the process exits. Setting handler to nil flushes safely.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any trailing partial line (no newline at EOF).
        for line in stdoutSplitter.flush() {
            for event in parser.parse(line: line) {
                onEvent(event)
            }
        }

        let exitCode = process.terminationStatus

        if timedOut {
            onEvent(.turnFailed(reason: "Chat turn timed out after \(Int(effectiveTimeout))s."))
        } else if !parser.didEmitTerminalEvent {
            // CLI exited without a `result` event — surface stderr if present.
            let stderr = stderrTail.snapshot().trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = stderr.isEmpty
                ? "Claude exited (\(exitCode)) without a result event."
                : "Claude failed: \(String(stderr.prefix(300)))"
            onEvent(.turnFailed(reason: reason))
        }

        onEvent(.terminated(exitCode: exitCode))

        await ErrorLogger.shared.log(
            area: "ClaudeChat.TurnRunner.finished",
            message: "Chat turn complete",
            context: [
                "exitCode": "\(exitCode)",
                "timedOut": "\(timedOut)"
            ]
        )
    }

    /// Park a continuation until the process exits. Same `terminationHandler`
    /// pattern as `WeeklyRhythmEngineRunner` — `waitUntilExit()` would race
    /// our concurrent pipe drain.
    private static func waitForExit(process: Process) async {
        let resumer = SingleResumer()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            resumer.set(continuation)
            process.terminationHandler = { _ in
                resumer.resumeOnce()
            }
            if !process.isRunning {
                resumer.resumeOnce()
            }
        }
    }

    private static func makeUserEventJSON(text: String) -> String {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": text]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}

// MARK: - SingleResumer
//
// One-shot continuation guard. `CheckedContinuation` traps on double-resume,
// and our terminationHandler-vs-already-exited race could fire twice. This
// wrapper makes the second call a no-op. Mirrors the same pattern in
// `WeeklyRhythmEngineRunner`.

private final class SingleResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    func set(_ c: CheckedContinuation<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        continuation = c
    }

    func resumeOnce() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume()
    }
}

// MARK: - LineSplitter
//
// Buffers partial chunks across `readabilityHandler` invocations and emits
// only complete lines. Mirrors the same pattern in `WeeklyRhythmEngineRunner`
// (kept private here so each subsystem owns its own buffer state).

private final class LineSplitter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.ClaudeChat.LineSplitter")
    private var pending: String = ""

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

    func flush() -> [String] {
        queue.sync {
            guard !pending.isEmpty else { return [] }
            let result = [pending]
            pending = ""
            return result
        }
    }
}

// MARK: - Tail buffer (stderr capture)
//
// Last ~4KB of stderr. Used only as a fallback if the CLI exits without
// emitting a `result` event — we want SOMETHING to show the user.

private final class TailBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.ClaudeChat.TailBuffer")
    private var content: String = ""
    private let limit = 4000

    func append(_ s: String) {
        queue.sync {
            content += s
            if content.count > limit {
                content = String(content.suffix(limit))
            }
        }
    }

    func snapshot() -> String {
        queue.sync { content }
    }
}

// MARK: - Stream Parser
//
// One JSON event per line. We surface:
//   - `stream_event.content_block_delta.text_delta` → `.partialAssistantText` (live caret)
//   - full `assistant` events → index tool_use_id → (name, input) for pairing
//   - `user.tool_result` events → emit `.toolUseCompleted` with paired metadata
//   - `result` event → terminal `.turnComplete` / `.turnFailed`
// Everything else (system init, status, replay user-messages, thinking deltas,
// content_block_start/stop, message_start/stop) is silently ignored.
//
// Uses JSONSerialization rather than Codable because tool_use `input` is an
// arbitrary nested object that's easier to re-serialize as a string than to
// model with Codable.

private final class ChatStreamParser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FortAbode.ClaudeChat.StreamParser")
    private var pendingToolUses: [String: (name: String, input: String)] = [:]
    private var emittedTerminal: Bool = false
    private var didEmitPlan: Bool = false

    var didEmitTerminalEvent: Bool {
        queue.sync { emittedTerminal }
    }

    func parse(line: String) -> [ClaudeChatEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let type = obj["type"] as? String ?? ""
        switch type {
        case "stream_event": return handleStreamEvent(obj)
        case "assistant":    return handleAssistantEvent(obj)
        case "user":         return handleUserEvent(obj)
        case "result":       return handleResultEvent(obj)
        default:             return []
        }
    }

    private func handleStreamEvent(_ obj: [String: Any]) -> [ClaudeChatEvent] {
        guard let event = obj["event"] as? [String: Any],
              (event["type"] as? String) == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              (delta["type"] as? String) == "text_delta",
              let text = delta["text"] as? String else {
            return []
        }
        return [.partialAssistantText(text)]
    }

    private func handleAssistantEvent(_ obj: [String: Any]) -> [ClaudeChatEvent] {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }
        var emitted: [ClaudeChatEvent] = []
        for block in content {
            guard (block["type"] as? String) == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { continue }
            let inputDict = block["input"] as? [String: Any]
            let inputJSON: String
            if let input = inputDict,
               let data = try? JSONSerialization.data(withJSONObject: input),
               let s = String(data: data, encoding: .utf8) {
                inputJSON = s
            } else {
                inputJSON = ""
            }

            // In `--permission-mode plan`, Claude calls the Plan tool (and
            // sometimes ExitPlanMode) with the plan markdown in `input.plan`.
            // Capture the FIRST occurrence as a planDrafted event so the
            // store can surface the Plan Card.
            if (name == "Plan" || name == "ExitPlanMode"),
               let plan = inputDict?["plan"] as? String,
               !plan.isEmpty {
                let shouldEmit = queue.sync { () -> Bool in
                    if didEmitPlan { return false }
                    didEmitPlan = true
                    return true
                }
                if shouldEmit {
                    emitted.append(.planDrafted(plan: plan))
                }
                // Don't track Plan/ExitPlanMode for breadcrumb pairing — they
                // are implementation detail of plan mode, not user-visible
                // tool calls.
                continue
            }

            queue.sync { pendingToolUses[id] = (name, inputJSON) }
        }
        return emitted
    }

    private func handleUserEvent(_ obj: [String: Any]) -> [ClaudeChatEvent] {
        guard let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }
        var events: [ClaudeChatEvent] = []
        for block in content {
            guard (block["type"] as? String) == "tool_result",
                  let id = block["tool_use_id"] as? String else { continue }
            let isError = (block["is_error"] as? Bool) ?? false
            let outputContent = Self.extractToolResultContent(block["content"])
            let pair = queue.sync { () -> (String, String)? in
                guard let p = pendingToolUses[id] else { return nil }
                pendingToolUses.removeValue(forKey: id)
                return (p.name, p.input)
            }
            guard let (name, input) = pair else { continue }
            events.append(.toolUseCompleted(
                name: name,
                input: input,
                succeeded: !isError,
                output: outputContent
            ))
        }
        return events
    }

    private func handleResultEvent(_ obj: [String: Any]) -> [ClaudeChatEvent] {
        let isError = (obj["is_error"] as? Bool) ?? false
        let resultText = (obj["result"] as? String) ?? ""
        queue.sync { emittedTerminal = true }
        if isError {
            let reason = resultText.isEmpty ? "Turn failed without a reason" : resultText
            return [.turnFailed(reason: reason)]
        }
        return [.turnComplete(fullText: resultText)]
    }

    /// `tool_result.content` may be a String OR an array of `{type:"text", text:"..."}` blocks.
    private static func extractToolResultContent(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        if let arr = raw as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}
