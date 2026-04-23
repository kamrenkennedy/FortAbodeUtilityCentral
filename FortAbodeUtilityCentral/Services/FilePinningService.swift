import Foundation

/// Pins iCloud folders locally via `brctl download` so Claude Memory, Deep Context,
/// Weekly Rhythm, Family Memory, and CLAUDE.md are always available offline.
///
/// Runs in two places:
///   1. Post-install of the Memory or Weekly Rhythm component (first-time pin).
///   2. App launch (`pinAll()` from `FortAbodeUtilityCentralApp.onAppear`) so macOS
///      cache eviction is undone on every open and new files get pinned too.
///
/// The historical bug fixed in v3.7.1: the base path was hardcoded as
/// `~/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory` with subfolders
/// `Kennedy Family Docs/Claude` and `Weekly Rhythm` appended — but those folders live
/// at the iCloud root, not inside Claude Memory. The `fileExists` guard silently
/// dropped the pin on every non-existent path. This rewrite uses two explicit root
/// targets and walks the tree recursively so every subdirectory gets pinned.
actor FilePinningService {

    /// Root folders that should always be kept downloaded.
    /// Each one is expanded recursively — every subdirectory is also pinned.
    private var targetRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let iCloudRoot = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"
        return [
            "\(iCloudRoot)/Claude Memory",
            "\(iCloudRoot)/Kennedy Family Docs/Claude",
            "\(iCloudRoot)/Kennedy Family Docs/Weekly Rhythm"
        ]
    }

    /// Pin every target root and all of its subdirectories recursively.
    /// Safe to call at any time — missing folders are skipped gracefully.
    func pinAll() async {
        let fm = FileManager.default

        for root in targetRoots {
            guard fm.fileExists(atPath: root) else {
                // Folder doesn't exist yet on this machine — e.g. Tiera's Mac before
                // she runs `npx setup-claude-memory --family`. Skip silently.
                continue
            }

            // Pin the root itself
            _ = await pin(path: root)

            // Walk the tree and pin every subdirectory so nested folders like
            // Weekly Rhythm/Kamren/dashboards/ get downloaded too. brctl download is
            // non-recursive by default, so we explicitly enumerate.
            await pinSubdirectories(of: root, fileManager: fm)
        }
    }

    /// Enumerate every subdirectory under `root` and pin it.
    private func pinSubdirectories(of root: String, fileManager fm: FileManager) async {
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        while let url = enumerator.nextObject() as? URL {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                _ = await pin(path: url.path)
            }
        }
    }

    /// Run `brctl download <path>` and return whether it succeeded.
    @discardableResult
    private func pin(path: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        process.arguments = ["download", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            await ErrorLogger.shared.log(
                componentId: "icloud-pinning",
                displayName: "iCloud Folder Pinning",
                error: "brctl download failed for \(path): \(error.localizedDescription)",
                installedVersion: nil
            )
            return false
        }
    }
}
