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

    /// Probe Claude's MCP configuration from two sources, merged:
    ///
    /// 1. `claude mcp list` — the live CLI invocation. Sees Anthropic-hosted
    ///    MCPs (`claude.ai *` entries served over HTTPS, accessible regardless
    ///    of CWD) plus any user-scoped local MCPs.
    ///
    /// 2. `~/.claude.json` — the on-disk config. Read directly to discover
    ///    project-scoped MCPs that `claude mcp list` only shows when invoked
    ///    inside the matching project tree. The Fort Abode .app launches with
    ///    CWD `/`, so without this fallback the probe misses every
    ///    project-scoped local stdio MCP (apple-reminders, Kam-Memory, etc.).
    ///
    /// Source 1 is authoritative for connection status (✓ Connected). Source 2
    /// only proves CONFIGURED, not connected — but for the preflight heuristic
    /// "configured" is the right signal, since the engine itself surfaces the
    /// real failure if a tool is broken. We fail-open: probeFailed = true only
    /// when BOTH sources fail.
    public func probe(cliPath: String) async -> ProbeResult {
        // Source 1: live CLI
        var cliConnected: Set<String> = []
        var cliFailed = false
        let outcome = await Self.runProcess(cliPath: cliPath, arguments: ["mcp", "list"])
        if outcome.exitCode == 0 {
            cliConnected = Self.parseConnected(from: outcome.stdout)
        } else {
            cliFailed = true
            await ErrorLogger.shared.log(
                area: "MCPProbe.probe",
                message: "claude mcp list failed",
                context: [
                    "exitCode": "\(outcome.exitCode)",
                    "stderr": String(outcome.stderr.prefix(500)),
                    "stdout": String(outcome.stdout.prefix(500))
                ]
            )
        }

        // Source 2: ~/.claude.json (CWD-independent)
        let jsonConfigured = Self.readConfiguredFromClaudeJSON()

        let merged = cliConnected.union(jsonConfigured)
        let missing = Self.missingRequirements(in: merged)

        await ErrorLogger.shared.log(
            area: "MCPProbe.probe",
            message: "probe complete",
            context: [
                "cliConnectedCount": "\(cliConnected.count)",
                "cliConnected": cliConnected.sorted().joined(separator: ", "),
                "jsonConfiguredCount": "\(jsonConfigured.count)",
                "jsonConfigured": jsonConfigured.sorted().joined(separator: ", "),
                "mergedCount": "\(merged.count)",
                "missing": missing.map(\.displayName).joined(separator: ", "),
                "cliFailed": "\(cliFailed)"
            ]
        )

        // Only flag probeFailed if BOTH sources failed entirely.
        let probeFailed = cliFailed && jsonConfigured.isEmpty
        return ProbeResult(connected: merged, probeFailed: probeFailed)
    }

    /// Read `~/.claude.json` and return the union of MCP names from the
    /// user-scoped `mcpServers` map and every project-scoped
    /// `projects.<path>.mcpServers` map. CWD-independent — works regardless
    /// of where the host process is launched from. Returns an empty set on
    /// any read/parse error (caller fails open).
    static func readConfiguredFromClaudeJSON() -> Set<String> {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude.json")
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var names: Set<String> = []
        if let userScope = json["mcpServers"] as? [String: Any] {
            names.formUnion(userScope.keys)
        }
        if let projects = json["projects"] as? [String: Any] {
            for (_, proj) in projects {
                guard let projDict = proj as? [String: Any],
                      let mcps = projDict["mcpServers"] as? [String: Any] else {
                    continue
                }
                names.formUnion(mcps.keys)
            }
        }
        return names
    }

    // MARK: - Heuristic

    /// Compute the requirements that are NOT covered by the configured set.
    /// Uses the same normalize/substring matcher as `isRequirementCovered`.
    public static func missingRequirements(in configured: Set<String>) -> [Requirement] {
        requirements.filter { !isRequirementCovered($0, in: configured) }
    }

    /// True iff at least one of the requirement's candidate names appears as
    /// a substring of any configured MCP's name, after normalizing both sides
    /// (lowercase, strip non-alphanumeric). Shared by both
    /// `missingRequirements` (preflight dialog) and the per-row connection
    /// status in `SynthesizedRunReport` (Run Health modal). Normalization
    /// makes the matching robust to real-world variations:
    ///   - `claude.ai Gmail` (space + period) matches `gmail`
    ///   - `claude.ai Google Calendar` matches `google-calendar` (space ↔ hyphen)
    ///   - `Kam-Memory` matches `memory` (case insensitive)
    ///   - `google-workspace` matches `gws` (also a candidate explicitly listed)
    public static func isRequirementCovered(
        _ requirement: Requirement,
        in configured: Set<String>
    ) -> Bool {
        let normalizedConfigured = configured.map { Self.normalize($0) }
        let normalizedCandidates = requirement.candidateNames.map { Self.normalize($0) }
        for configuredName in normalizedConfigured {
            for candidate in normalizedCandidates where configuredName.contains(candidate) {
                return true
            }
        }
        return false
    }

    /// Lowercase + strip everything that isn't a letter or digit. Lets the
    /// substring matcher treat `claude.ai Google Calendar`, `google-calendar`,
    /// and `googleCalendar` as equivalent for capability detection.
    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Parsing

    /// Parse `claude mcp list` output. Format observed in Claude Code 2.1.x:
    ///
    /// ```
    /// Checking MCP server health…
    ///
    /// kam-memory: npx -y mcp-knowledge-graph --memory-path … - ✓ Connected
    /// google-workspace: npx -y @aaronsb/google-workspace-mcp - ✓ Connected
    /// claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✓ Connected
    /// some-broken: bad-command - ✗ Failed: connection refused
    /// ```
    ///
    /// We only return the names where the line contains a "✓" / "Connected"
    /// status — Failed entries don't count for the requirements heuristic.
    /// Names with spaces (like `claude.ai Gmail`) are kept; only the standalone
    /// header line "Checking MCP server health…" needs to be skipped, which
    /// we filter via the absence of a `: ` separator (header has no colon
    /// or has a colon followed immediately by something non-MCP-shaped).
    static func parseConnected(from output: String) -> Set<String> {
        var names: Set<String> = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            // Require a `: ` (colon then space) to filter out lines like the
            // header "Checking MCP server health…" that may contain other
            // colons (e.g., a URL in a future format) but not in this shape.
            guard let colonRange = line.range(of: ": ") else { continue }
            let name = String(line[..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            // Only count connected MCPs. The CLI uses ✓ / ✗ glyphs;
            // "Connected" / "Failed" hedge against future glyph changes.
            // Avoid matching "Connected" within a "Failed: connection ..."
            // string by also requiring the ✓ glyph or end-of-line "Connected".
            if line.contains("✓") || line.contains("- Connected") {
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
