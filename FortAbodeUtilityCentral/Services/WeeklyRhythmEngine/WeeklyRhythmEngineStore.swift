import Foundation
import Observation
import AppKit

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

    // MARK: - Live Mode v0.1 state (v3.12.0)
    //
    // Foreground auto-run + opt-in background timer. The "always-on assistant"
    // direction starts here — instead of the dashboard sitting stale between
    // manual run-button presses, the engine re-runs at the right moments.

    private var activationObserver: NSObjectProtocol?
    private var seenFirstActivation: Bool = false
    private var lastForegroundCheck: Date?
    private var backgroundTimerTask: Task<Void, Never>?

    /// Quick alt-tab debounce. The real gate for foreground auto-runs is the
    /// hours-since-last-run threshold; this just prevents back-to-back fires
    /// from rapid window cycling (cmd-tab into the app, cmd-tab back out, etc).
    private static let foregroundCooldown: TimeInterval = 60

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

    /// Probe `claude mcp list` independently of an engine run. Called at app
    /// launch (after CLI detection) so the Engine Status modal has real
    /// per-MCP connectivity to render even when the user hasn't kicked off
    /// an engine run yet — without it the modal falls through to the
    /// `RunReport.synthesized(...)` fallback with no probe data, which means
    /// every MCP row renders as `.neutral` with em-dash placeholders.
    /// Best-effort: if the CLI isn't found yet the call is a no-op, and any
    /// probe failure leaves `lastMCPProbe == nil` so the synthesizer still
    /// shows the polite neutral state instead of a false red.
    public func probeMCPsIfPossible() async {
        guard case .found(let path, _) = cliDetection else { return }
        let probe = await mcpProbe.probe(cliPath: path)
        // Only overwrite an existing probe if the new one didn't fail —
        // a successful probe from an earlier run is more useful than a
        // failed launch-time probe.
        if !probe.probeFailed || lastMCPProbe == nil {
            lastMCPProbe = probe
        }
    }

    // MARK: - Manual run

    /// Spawn the engine via the embedded CLI. Updates `runState` through the
    /// lifecycle and posts a system notification on completion (unless the user
    /// has muted via Settings). Phase 6.1: probe for the skill first and
    /// surface `.needsSkill` if it's not installed — the UI presents an
    /// install sheet rather than running blind and getting an opaque CLI
    /// error.
    ///
    /// `silent: true` is for auto-triggered runs (foreground auto-run, the
    /// background timer) — they bail early on missing CLI/skill instead of
    /// transitioning into states that drive surprise sheets, and they proceed
    /// with degraded MCPs (engine v2.5.0's reduced-mode emission rules emit
    /// warnings into the run report so the attention banner still surfaces
    /// what degraded). Manual runs (`silent: false`, default) keep the full
    /// guided sheet flow.
    public func runNow(silent: Bool = false) async {
        // Always re-detect right before a run so a freshly-installed CLI gets
        // picked up without forcing a Settings round-trip.
        if case .notFound = cliDetection {
            cliDetection = await detector.detect()
        }

        guard case .found(let path, _) = cliDetection else {
            if silent { return }
            runState = .failed(error: "Claude CLI not found. Install it from claude.ai/code or pin a custom path in Settings.")
            return
        }

        // Skill probe — if missing, hand back to the UI so the user can
        // choose to install. The view layer calls `installSkillThenRun()`
        // when they accept. Auto-runs don't surface install sheets.
        let skillInstalled = await installer.detectInstalled(cliPath: path)
        guard skillInstalled else {
            if silent { return }
            runState = .needsSkill
            return
        }

        // MCP pre-flight — if any required group is uncovered, hand back to
        // the UI for a "Run anyway?" decision. Probe failures fail open.
        // Auto-runs proceed with whatever's connected; the engine's
        // reduced-mode emission produces a partial dashboard with warnings.
        let probe = await mcpProbe.probe(cliPath: path)
        lastMCPProbe = probe
        if !probe.probeFailed {
            let missing = MCPProbe.missingRequirements(in: probe.connected)
            if !missing.isEmpty && !silent {
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

        // Per-run timeout: read the user's Settings preference at run time so
        // changes take effect without an app relaunch. 0 (the default for
        // never-set) → use the runner's static default.
        let configuredMinutes = UserDefaults.standard.integer(forKey: AppSettingsKey.weeklyRhythmEngineTimeoutMinutes)
        let timeoutOverride: Double? = configuredMinutes > 0 ? Double(configuredMinutes) * 60 : nil

        let result = await runner.run(cliPath: cliPath, timeoutSecondsOverride: timeoutOverride) { [weak self] progress in
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

    // MARK: - Live Mode v0.1: foreground auto-run
    //
    // Mirrors `AppUpdaterService.startObservingActivation()`'s shape — listen
    // for `NSApplication.didBecomeActiveNotification`, skip the first
    // activation (engine has its own launch-time detect/probe pass on
    // `.onAppear`), and on subsequent activations re-run the engine if the
    // last successful run is older than the user's threshold.

    /// Wire up the foreground auto-run observer. Idempotent — safe to call
    /// from `.onAppear` on every render. Called from
    /// `FortAbodeUtilityCentralApp.detectEngineCLI()`.
    public func startObservingActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees the closure runs on the main thread,
            // so MainActor.assumeIsolated is safe under Swift 6 strict
            // concurrency. Same pattern as AppUpdaterService.
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.seenFirstActivation {
                    self.seenFirstActivation = true
                    return
                }
                if let last = self.lastForegroundCheck,
                   Date().timeIntervalSince(last) < Self.foregroundCooldown {
                    return
                }
                self.lastForegroundCheck = Date()
                Task { @MainActor in
                    await self.runIfStaleOnForeground()
                }
            }
        }
    }

    /// Decide whether to fire an auto-run on a foreground activation. The
    /// real gate is the user's hours-since-last-run threshold; the alt-tab
    /// debounce in `startObservingActivation` is just a guardrail.
    private func runIfStaleOnForeground() async {
        let defaults = UserDefaults.standard
        // Default ON. Reading via `object(forKey:)` so we can distinguish
        // "user explicitly disabled" from "never set."
        let enabled = defaults.object(forKey: AppSettingsKey.weeklyRhythmEngineAutoRunOnForeground) as? Bool ?? true
        guard enabled else { return }

        // Don't trample an in-flight run or a state that's waiting on user
        // input. Idle / succeeded / failed are all safe to re-run from.
        switch runState {
        case .idle, .succeeded, .failed:
            break
        default:
            return
        }

        let thresholdHours = defaults.object(forKey: AppSettingsKey.weeklyRhythmEngineForegroundThresholdHours) as? Int ?? 6
        let lastRunAt = defaults.double(forKey: AppSettingsKey.weeklyRhythmEngineLastRunAt)
        if lastRunAt > 0 {
            let elapsed = Date().timeIntervalSince(Date(timeIntervalSince1970: lastRunAt))
            if elapsed < TimeInterval(max(1, thresholdHours)) * 3600 { return }
        }

        await runNow(silent: true)
    }

    // MARK: - Live Mode v0.1: background timer
    //
    // Opt-in. Off by default — running the engine costs tokens, and the
    // foreground auto-run already covers most "I just opened the app, give
    // me fresh data" cases. The timer is for users who leave Fort Abode
    // open all day and want it to refresh on a cadence.

    /// Reconcile the timer with the user's current settings. Cancel any
    /// running task, then start a fresh one if the toggle is on. Called from
    /// `.onAppear` and from the Settings toggle/picker `onChange` so changes
    /// take effect without an app relaunch.
    public func applyBackgroundTimerSettings() {
        backgroundTimerTask?.cancel()
        backgroundTimerTask = nil

        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: AppSettingsKey.weeklyRhythmEngineBackgroundTimerEnabled) as? Bool ?? false
        guard enabled else { return }

        let intervalMinutes = max(15, defaults.object(forKey: AppSettingsKey.weeklyRhythmEngineBackgroundTimerMinutes) as? Int ?? 60)
        let intervalSeconds = TimeInterval(intervalMinutes) * 60

        backgroundTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled, let self else { return }

                // Re-read the toggle each iteration in case the user disabled
                // the timer during the sleep window.
                let stillEnabled = UserDefaults.standard.object(forKey: AppSettingsKey.weeklyRhythmEngineBackgroundTimerEnabled) as? Bool ?? false
                guard stillEnabled else { return }

                switch self.runState {
                case .idle, .succeeded, .failed:
                    await self.runNow(silent: true)
                default:
                    continue
                }
            }
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
