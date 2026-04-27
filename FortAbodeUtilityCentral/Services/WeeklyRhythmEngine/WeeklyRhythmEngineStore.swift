import Foundation
import Observation

// MARK: - Engine Store
//
// `@Observable` UI-facing state for the embedded engine runner. Mirrors the
// `WeeklyRhythmStore` (Phase 5a) pattern — one store, one impl, MainActor for
// SwiftUI integration. Owns the detector + runner; views observe `runState`,
// `cliDetection`, and `lastRunResult`.
//
// Persistence: `lastRunResult`'s identity-bearing fields (timestamp, success,
// summary) round-trip through `@AppStorage`-equivalent UserDefaults keys so
// the run pill survives an app relaunch (e.g. after a LaunchAgent-driven
// background run that exited the app).

@MainActor
@Observable
public final class WeeklyRhythmEngineStore {

    public enum RunState: Sendable, Equatable {
        case idle
        case detecting
        case running(progress: String)
        case installingSkill(progress: String)
        case needsSkill
        case missingMCPs([MCPProbe.Requirement])
        case succeeded(result: RunResult)
        case failed(error: String)
    }

    public private(set) var runState: RunState = .idle
    public private(set) var cliDetection: ClaudeCLIDetector.Result = .notFound
    public private(set) var lastRunResult: RunResult?
    public private(set) var lastMCPProbe: MCPProbe.ProbeResult?

    private let detector: ClaudeCLIDetector
    private let runner: WeeklyRhythmEngineRunner
    private let installer: WeeklyRhythmSkillInstaller
    private let mcpProbe: MCPProbe

    public init(
        detector: ClaudeCLIDetector = ClaudeCLIDetector(),
        runner: WeeklyRhythmEngineRunner = WeeklyRhythmEngineRunner(),
        installer: WeeklyRhythmSkillInstaller = WeeklyRhythmSkillInstaller(),
        mcpProbe: MCPProbe = MCPProbe()
    ) {
        self.detector = detector
        self.runner = runner
        self.installer = installer
        self.mcpProbe = mcpProbe
        self.lastRunResult = Self.loadPersistedLastRun()
    }

    // MARK: - CLI detection

    /// Run the detection waterfall and cache the result. Safe to call repeatedly
    /// — the dropdown's "Force re-detect" hook in Settings reuses this.
    public func detectCLI() async {
        // Don't trample an in-flight run with a `.detecting` flicker.
        let priorState = runState
        if case .running = priorState {
            // Refresh detection silently while a run is in flight.
            cliDetection = await detector.detect()
            return
        }
        runState = .detecting
        cliDetection = await detector.detect()
        runState = .idle
    }

    // MARK: - Manual run

    /// Spawn the engine via the embedded CLI. Updates `runState` through the
    /// lifecycle and posts a system notification on completion (unless the user
    /// has muted via Settings). Phase 6.1: probe for the skill first and
    /// surface `.needsSkill` if it's not installed — the UI presents an
    /// install sheet rather than running blind and getting an opaque CLI
    /// error.
    public func runNow() async {
        // Always re-detect right before a run so a freshly-installed CLI gets
        // picked up without forcing a Settings round-trip.
        if case .notFound = cliDetection {
            cliDetection = await detector.detect()
        }

        guard case .found(let path, _) = cliDetection else {
            runState = .failed(error: "Claude CLI not found. Install it from claude.ai/code or pin a custom path in Settings.")
            return
        }

        // Skill probe — if missing, hand back to the UI so the user can
        // choose to install. The view layer calls `installSkillThenRun()`
        // when they accept.
        let skillInstalled = await installer.detectInstalled(cliPath: path)
        guard skillInstalled else {
            runState = .needsSkill
            return
        }

        // MCP pre-flight — if any required group is uncovered, hand back to
        // the UI for a "Run anyway?" decision. Probe failures fail open.
        let probe = await mcpProbe.probe(cliPath: path)
        lastMCPProbe = probe
        if !probe.probeFailed {
            let missing = MCPProbe.missingRequirements(in: probe.connected)
            if !missing.isEmpty {
                runState = .missingMCPs(missing)
                return
            }
        }

        await runEngine(cliPath: path)
    }

    /// Bypass the missing-MCP warning and run anyway. Called from the warning
    /// sheet's "Run anyway" button — the engine might still partial-succeed
    /// even with one MCP missing, so we don't hard-block.
    public func runAnywayAfterMissingMCPs() async {
        guard case .found(let path, _) = cliDetection else {
            runState = .failed(error: "Claude CLI not found.")
            return
        }
        await runEngine(cliPath: path)
    }

    /// Drop the `.missingMCPs` state back to idle when the user dismisses the
    /// warning sheet without proceeding.
    public func cancelMissingMCPs() async {
        if case .missingMCPs = runState {
            runState = .idle
        }
    }

    /// Drop the `.needsSkill` state back to idle when the user dismisses the
    /// install sheet without proceeding. Used as the sheet's onDismiss.
    public func cancelNeedsSkill() async {
        if runState == .needsSkill {
            runState = .idle
        }
    }

    /// Run the three-step skill install, then immediately run the engine on
    /// success. Called from the install sheet's "Install & Run" action.
    public func installSkillThenRun() async {
        guard case .found(let path, _) = cliDetection else {
            runState = .failed(error: "Claude CLI not found.")
            return
        }
        runState = .installingSkill(progress: "Installing Weekly Rhythm Engine skill…")
        let outcome = await installer.install(cliPath: path)
        switch outcome {
        case .alreadyInstalled, .installed:
            await runEngine(cliPath: path)
        case .failed(let step, let output):
            runState = .failed(error: "\(step) failed.\n\n\(output)")
        }
    }

    /// Drive the engine itself. Extracted so the manual run path and the
    /// install-then-run path share the same end-to-end body.
    private func runEngine(cliPath: String) async {
        runState = .running(progress: "Starting engine…")

        let result = await runner.run(cliPath: cliPath) { [weak self] progress in
            // `onProgress` runs off-main; hop back to update observed state.
            guard let self else { return }
            Task { @MainActor in
                if case .stdoutLine(let line) = progress, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.runState = .running(progress: line)
                }
            }
        }

        lastRunResult = result
        Self.persistLastRun(result)

        if result.succeeded {
            runState = .succeeded(result: result)
        } else {
            runState = .failed(error: result.summary)
        }

        let surface = UserDefaults.standard.object(forKey: AppSettingsKey.weeklyRhythmEngineSurfaceOnCompletion) as? Bool ?? true
        if surface {
            await NotificationService.shared.postEngineRunNotification(
                succeeded: result.succeeded,
                summary: result.summary
            )
        }
    }

    // MARK: - Persistence
    //
    // Round-trips the last run summary through UserDefaults so a relaunch
    // (after a background-only `--run-engine` invocation that exited the app)
    // keeps the run pill labeled "Last run 2h ago — succeeded · …" instead of
    // re-zeroing to "Idle."

    private static let persistedRunFinishedAtKey = AppSettingsKey.weeklyRhythmEngineLastRunAt
    private static let persistedRunSucceededKey  = AppSettingsKey.weeklyRhythmEngineLastRunSucceeded
    private static let persistedRunSummaryKey    = AppSettingsKey.weeklyRhythmEngineLastRunSummary

    private static func loadPersistedLastRun() -> RunResult? {
        let defaults = UserDefaults.standard
        let timestamp = defaults.double(forKey: persistedRunFinishedAtKey)
        guard timestamp > 0,
              let summary = defaults.string(forKey: persistedRunSummaryKey) else {
            return nil
        }
        let succeeded = defaults.bool(forKey: persistedRunSucceededKey)
        return RunResult(
            succeeded: succeeded,
            durationSeconds: 0,
            summary: summary,
            stdoutTail: "",
            stderrTail: "",
            finishedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private static func persistLastRun(_ result: RunResult) {
        let defaults = UserDefaults.standard
        // Persist as TimeInterval so @AppStorage(... Double) can read it back
        // in `WeeklyRhythmEngineSection`. Date doesn't round-trip through
        // @AppStorage cleanly without a custom RawRepresentable.
        defaults.set(result.finishedAt.timeIntervalSince1970, forKey: persistedRunFinishedAtKey)
        defaults.set(result.succeeded, forKey: persistedRunSucceededKey)
        defaults.set(result.summary, forKey: persistedRunSummaryKey)
    }
}
