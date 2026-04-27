import Foundation

// MARK: - MCP Probe (Phase 6.1)
//
// Asks `claude mcp list` what MCPs are configured + connected on the user's
// machine, and exposes a best-effort heuristic for the Weekly Rhythm Engine's
// known requirements (Gmail / Google Calendar / Reminders / Memory / Notion).
//
// The heuristic is fail-open: a required group is "satisfied" if ANY of its
// candidate names appear in the configured set. Rationale — there's no
// canonical naming convention; Kam's machine has `google-workspace` (which
// covers Gmail+GCal+Tasks via @aaronsb/google-workspace-mcp), Tiera's might
// have separate `gmail`+`gcal`. The engine ultimately calls tools, not MCPs
// by name, so any MCP that exposes the right tools works. The probe is a
// preflight nudge, not a gate.

public struct MCPProbe: Sendable {

    public struct Requirement: Sendable, Equatable, Identifiable {
        public let displayName: String
        public let candidateNames: Set<String>
        public var id: String { displayName }
    }

    /// Engine requirements — each entry says "these MCPs all provide the same
    /// capability; the user needs at least one." The candidate sets capture
    /// the patterns we've seen on Kam's + Tiera's machines so far. New MCPs
    /// providing the same capability can just be added here.
    public static let requirements: [Requirement] = [
        Requirement(
            displayName: "Gmail",
            candidateNames: ["gmail", "google-workspace", "gws"]
        ),
        Requirement(
            displayName: "Google Calendar",
            candidateNames: ["google-calendar", "gcal", "google-workspace", "gws"]
        ),
        Requirement(
            displayName: "Apple Reminders",
            candidateNames: ["apple-reminders", "reminders"]
        ),
        Requirement(
            displayName: "Memory",
            candidateNames: ["memory", "kam-memory", "tiera-memory"]
        ),
        Requirement(
            displayName: "Notion",
            candidateNames: ["notion", "notion-tiera", "notion-kam"]
        ),
    ]

    public init() {}

    // MARK: - Probe

    public struct ProbeResult: Sendable, Equatable {
        public let connected: Set<String>
        public let probeFailed: Bool

        public init(connected: Set<String>, probeFailed: Bool) {
            self.connected = connected
            self.probeFailed = probeFailed
        }
    }

    /// Run `claude mcp list` and parse the result. Returns the set of MCP
    /// names that report as Connected. On any CLI failure, returns
    /// `probeFailed: true` with an empty set so the caller can decide whether
    /// to block (we don't — fail open and run anyway).
    public func probe(cliPath: String) async -> ProbeResult {
        let outcome = await Self.runProcess(cliPath: cliPath, arguments: ["mcp", "list"])
        guard outcome.exitCode == 0 else {
            return ProbeResult(connected: [], probeFailed: true)
        }
        return ProbeResult(connected: Self.parseConnected(from: outcome.stdout), probeFailed: false)
    }

    // MARK: - Heuristic

    /// Compute the requirements that are NOT covered by the configured set.
    /// "Covered" = at least one candidate name appears in `configured`.
    public static func missingRequirements(in configured: Set<String>) -> [Requirement] {
        requirements.filter { req in
            req.candidateNames.intersection(configured).isEmpty
        }
    }

    // MARK: - Parsing

    /// Parse `claude mcp list` output. Format observed in Claude Code 2.1.x:
    ///
    /// ```
    /// Checking MCP server health…
    ///
    /// kam-memory: npx -y mcp-knowledge-graph --memory-path … - ✓ Connected
    /// google-workspace: npx -y @aaronsb/google-workspace-mcp - ✓ Connected
    /// some-broken: bad-command - ✗ Failed: connection refused
    /// ```
    ///
    /// We only return the names where the line contains a "✓" / "Connected"
    /// status — Failed entries don't count for the requirements heuristic.
    static func parseConnected(from output: String) -> Set<String> {
        var names: Set<String> = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let name = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
            // Skip header lines like "Checking MCP server health…" — those
            // either don't have a colon or have spaces in the prefix.
            guard !name.isEmpty, !name.contains(" ") else { continue }
            // Only count connected MCPs. The CLI uses ✓ / ✗ glyphs;
            // "Connected" / "Failed" hedge against future glyph changes.
            if line.contains("✓") || line.contains("Connected") {
                names.insert(name)
            }
        }
        return names
    }

    // MARK: - Process helper
    //
    // Same shape as WeeklyRhythmSkillInstaller's helper but factored out into
    // a static so the probe stays a value type (struct).

    private struct ProcessOutcome: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runProcess(cliPath: String, arguments: [String]) async -> ProcessOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ProcessOutcome, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = arguments

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

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: ProcessOutcome(
                        exitCode: -1,
                        stdout: "",
                        stderr: "Failed to spawn process: \(error.localizedDescription)"
                    ))
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessOutcome(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}
