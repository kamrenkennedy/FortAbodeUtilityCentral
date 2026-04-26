import Foundation

// Tiera-safe iCloud path resolution for the Weekly Rhythm engine folder.
//
// Two historical names exist in the wild: `Weekly Flow` (canonical per
// CLAUDE.md and what the engine writes to) and `Weekly Rhythm` (older name
// hardcoded in `WeeklyRhythmService` until this revision). Some machines have
// one, some have the other, neither is guaranteed.
//
// On Tiera's machine it's also possible that NEITHER folder exists yet — she
// may not have run the setup wizard. In that case the resolver returns nil
// and the data source falls back to mocks; nothing user-facing breaks.
//
// Resolution sequence:
//   1. `~/.../Kennedy Family Docs/Weekly Flow`
//   2. `~/.../Kennedy Family Docs/Weekly Rhythm`
//   3. nil (not configured on this machine)
//
// Active-user resolution (within the resolved root):
//   1. Caller-provided override (from `AppState.activeUserName` once we wire it)
//   2. The first subfolder containing a `config.md` file
//   3. nil (no user has run the engine yet)

public struct WeeklyRhythmPathResolver: Sendable {

    public init() {}

    public func resolve() -> Resolved? {
        let candidates = ResolvedRoot.allCases
        let fm = FileManager.default
        for candidate in candidates {
            if fm.fileExists(atPath: candidate.path) {
                return Resolved(root: candidate)
            }
        }
        return nil
    }

    // MARK: - Resolved root

    public enum ResolvedRoot: String, CaseIterable, Sendable {
        case weeklyFlow = "Weekly Flow"
        case weeklyRhythm = "Weekly Rhythm"

        public var path: String {
            let home = NSHomeDirectory()
            return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/\(rawValue)"
        }
    }

    public struct Resolved: Sendable {
        public let root: ResolvedRoot
        public var rootPath: String { root.path }

        init(root: ResolvedRoot) {
            self.root = root
        }

        /// Returns the user folder path for the given user name (e.g. "Kamren").
        /// Doesn't validate existence — caller checks if needed.
        public func userFolder(_ userName: String) -> String {
            "\(rootPath)/\(userName)"
        }

        /// Auto-detect the active user by scanning subfolders for the first one
        /// containing a `config.md`. Uses a local FileManager.default — safe to
        /// call from any actor since FileManager methods used here are stateless.
        public func detectActiveUser() -> String? {
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(atPath: rootPath) else {
                return nil
            }
            for entry in entries {
                let entryPath = "\(rootPath)/\(entry)"
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: entryPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                if fm.fileExists(atPath: "\(entryPath)/config.md") {
                    return entry
                }
            }
            return nil
        }

        /// Path to a per-user dashboards directory.
        public func dashboardsDir(for userName: String) -> String {
            "\(userFolder(userName))/dashboards"
        }

        /// Path to the JSON dump file for a given week-anchor date.
        /// Convention: `dashboard-{ISODate}.json` (e.g. `dashboard-2026-04-21.json`)
        /// where the date is the Monday of the requested week.
        public func dashboardJSONPath(for userName: String, isoDate: String) -> String {
            "\(dashboardsDir(for: userName))/dashboard-\(isoDate).json"
        }
    }
}
