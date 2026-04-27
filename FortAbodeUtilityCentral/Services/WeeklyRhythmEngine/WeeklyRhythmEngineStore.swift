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
        case succeeded(result: RunResult)
        case failed(error: String)
    }

    public private(set) var runState: RunState = .idle
    public private(set) var cliDetection: ClaudeCLIDetector.Result = .notFound
    public private(set) var lastRunResult: RunResult?

    private let detector: ClaudeCLIDetector
    private let runner: WeeklyRhythmEngineRunner

    public init(
        detector: ClaudeCLIDetector = ClaudeCLIDetector(),
        runner: WeeklyRhythmEngineRunner = WeeklyRhythmEngineRunner()
    ) {
        self.detector = detector
        self.runner = runner
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
    /// has muted via Settings).
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

        runState = .running(progress: "Starting engine…")

        let result = await runner.run(cliPath: path) { [weak self] progress in
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
