import Foundation

// Tiera-safe iCloud path resolution for the Weekly Rhythm engine folder.
//
// Two historical names exist in the wild: `Weekly Rhythm` (current canonical
// per Weekly Rhythm engine v2.1.0 release — what the engine writes to and
// what users' config.md `icloud_path` points to) and `Weekly Flow` (legacy
// name from before the v2.1.0 rename, may still exist as leftover state).
// Some machines have one, some have the other, neither is guaranteed.
//
// On Tiera's machine it's also possible that NEITHER folder exists yet — she
// may not have run the setup wizard. In that case the resolver returns nil
// and the data source falls back to mocks; nothing user-facing breaks.
//
// Resolution sequence (current canonical first, legacy second):
//   1. `~/.../Kennedy Family Docs/Weekly Rhythm` — engine writes here
//   2. `~/.../Kennedy Family Docs/Weekly Flow` — legacy fallback
//   3. nil (not configured on this machine)
//
// Active-user resolution (within the resolved root):
//   1. Caller-provided override (e.g. from `UserDefaults.weeklyRhythmActiveUserName`,
//      set by the setup wizard at install time)
//   2. macOS user identity match — `NSFullUserName().split(" ")[0]` matched
//      against subfolder names. Deterministic for the Kennedy family case where
//      folder names mirror first names ("Kamren", "Tiera").
//   3. The first subfolder containing a `config.md` file (legacy fallback;
//      relies on filesystem ordering and was the root cause of Kam's Mac
//      reading Tiera's dashboards before v3.12.0)
//   4. nil (no user has run the engine yet)

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
        case weeklyRhythm = "Weekly Rhythm"
        case weeklyFlow = "Weekly Flow"

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

        /// Match the macOS user's full name first-word against subfolder names.
        /// e.g. on Kam's Mac `NSFullUserName()` returns "Kamren Kennedy" → first
        /// word "Kamren" → matches the `Kamren/` subfolder. Same on Tiera's Mac
        /// for "Tiera". Deterministic and doesn't rely on filesystem ordering
        /// like `detectActiveUser` does.
        public func detectUserByMacOSIdentity() -> String? {
            let fullName = NSFullUserName()
            guard let firstWord = fullName.split(separator: " ").first.map(String.init),
                  !firstWord.isEmpty else { return nil }
            let fm = FileManager.default
            let candidate = "\(rootPath)/\(firstWord)"
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: candidate, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fm.fileExists(atPath: "\(candidate)/config.md") else { return nil }
            return firstWord
        }

        /// Legacy fallback: scan subfolders and return the first one containing a
        /// `config.md`. Order is filesystem-dependent — on a directory with both
        /// `Kamren/config.md` and `Tiera/config.md` it can return either. Use
        /// `detectUserByMacOSIdentity` first; this is the last-resort fallback.
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

        /// Sibling of `dashboardJSONPath` that the app writes to with queued
        /// user mutations (errand done, event move, proposal accept/decline).
        /// The engine drains it on its next run and renames to
        /// `…-pending.applied-{ISO}.json` for audit. See
        /// `Resources/dashboard-json-shape.md` for the engine-side spec.
        public func pendingMutationsPath(for userName: String, isoDate: String) -> String {
            "\(dashboardsDir(for: userName))/dashboard-\(isoDate)-pending.json"
        }

        /// Path to `{user}/config.md`. The engine reads this on every run; the
        /// app writes day-type edits surgically here.
        public func configPath(for userName: String) -> String {
            "\(userFolder(userName))/config.md"
        }
    }
}
