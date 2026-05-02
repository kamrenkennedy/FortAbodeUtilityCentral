import Foundation

// Synthesized RunReport for the Engine Status modal when the snapshot doesn't
// carry one. Engine v2.3.0 still doesn't emit a structured `runReport` blob in
// dashboard.json (Phase 8.1 contract gap, slated for engine v2.4.0); without
// this synthesizer the modal would render the static `MockWeeklyRhythmDataSource.
// runReport` and lie about the per-MCP connectivity ("All checks passed" + 5
// green dots even when the banner above is shouting "3 MCP sources degraded").
//
// Real inputs the app already has on hand:
//   • `WeeklyRhythmEngineStore.lastMCPProbe` — set of MCPs that reported
//     `✓ Connected` from the most recent `claude mcp list` probe (run before
//     each engine kickoff)
//   • `WeeklyRhythmEngineStore.lastRunResult` — finishedAt, durationSeconds,
//     succeeded, summary
//   • Snapshot's `runHealth` — the canonical degradation message ("Google
//     Calendar + Gmail personal only…") used as the recent-error entry
//
// When the engine eventually starts emitting runReport in dashboard.json,
// callers naturally fall through to that and this synthesizer becomes a
// fallback for Tiera's first-run-before-she's-ever-run-the-engine state.

extension RunReport {

    /// Build a best-effort report from local engine state when the snapshot's
    /// runReport is nil. Each MCP requirement (from `MCPProbe.requirements`)
    /// becomes a row whose status reflects real probe data when available.
    static func synthesized(
        probe: MCPProbe.ProbeResult?,
        lastRun: RunResult?,
        runHealth: RunHealth
    ) -> RunReport {
        let mcpStatuses = MCPProbe.requirements.map { req in
            mcpStatusRow(for: req, probe: probe)
        }

        let triggered: String
        if let lastRun {
            triggered = Self.relativeFormatter.localizedString(for: lastRun.finishedAt, relativeTo: Date())
        } else {
            triggered = "Engine not yet run"
        }

        let duration: String
        if let secs = lastRun?.durationSeconds, secs > 0 {
            let minutes = Int(secs) / 60
            let seconds = Int(secs) % 60
            duration = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        } else {
            duration = "—"
        }

        let outcome: String
        switch runHealth {
        case .allGood:        outcome = "All checks passed"
        case .warning:        outcome = "Issues detected"
        case .error:          outcome = "Run failed"
        }

        // recentErrors carries the engine's actual degradation message when
        // present, so the modal includes the same text the banner shows. The
        // synthesizer doesn't have access to ErrorLogger entries — that's a
        // separate channel — but this is enough to stop the modal lying.
        let recentErrors: [RunReportError]
        switch runHealth {
        case .allGood:
            recentErrors = []
        case .warning(let msg), .error(let msg):
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                recentErrors = []
            } else {
                let timestamp: String
                if let lastRun {
                    timestamp = Self.relativeFormatter.localizedString(for: lastRun.finishedAt, relativeTo: Date())
                } else {
                    timestamp = "—"
                }
                recentErrors = [RunReportError(
                    id: "synth-runhealth",
                    timestamp: timestamp,
                    message: trimmed
                )]
            }
        }

        return RunReport(
            mcpStatuses: mcpStatuses,
            triggered: triggered,
            duration: duration,
            outcome: outcome,
            engineVersion: "weekly-rhythm-engine v2.3.0",
            recentErrors: recentErrors
        )
    }

    // MARK: - Per-MCP rows

    private static func mcpStatusRow(
        for requirement: MCPProbe.Requirement,
        probe: MCPProbe.ProbeResult?
    ) -> MCPStatus {
        // If we have no probe at all (engine never run, or first launch on
        // Tiera's Mac), don't pretend to know — show neutral instead of red.
        guard let probe, !probe.probeFailed else {
            return MCPStatus(
                id: requirement.displayName,
                name: requirement.displayName,
                status: .neutral,
                version: "—",
                lastSuccess: probe?.probeFailed == true ? "Probe failed" : "—"
            )
        }

        let isConnected = MCPProbe.isRequirementCovered(requirement, in: probe.connected)
        return MCPStatus(
            id: requirement.displayName,
            name: requirement.displayName,
            status: isConnected ? .scheduled : .error,
            version: "—",
            lastSuccess: isConnected ? "Connected" : "Not connected"
        )
    }

    // MARK: - Formatter

    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
