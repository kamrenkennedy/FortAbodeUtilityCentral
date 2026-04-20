import Foundation

// MARK: - Full Disk Access Service

/// Detects whether Full Disk Access is available on this user account by
/// attempting a read of `~/Library/Messages/chat.db`.
///
/// This is a **proxy** for whether Claude Desktop has FDA. macOS provides no
/// API to query another app's TCC entry. In practice the grants travel together
/// — if the user grants FDA to one app the System Settings pane shows all
/// FDA-needing apps side-by-side, so the deep link surfaces both. When the
/// proxy fails the iMessage MCP cannot work either way, so the signal is
/// actionable even though it's not a direct query of Claude's grant.
enum FullDiskAccessService {

    /// macOS Settings deep link to Privacy & Security → Full Disk Access.
    static let systemSettingsDeepLink = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    /// Attempt to read the iMessage SQLite database. Returns true if FDA is
    /// granted to Fort Abode (and therefore grantable to Claude on this user
    /// account). Returns false on any error — the only failure mode that
    /// matters is `authorization denied`, but other errors (file missing on a
    /// fresh macOS install with no Messages history) also return false because
    /// in either case the iMessage MCP can't succeed.
    static func isGrantedForChatDB() -> Bool {
        let chatDBPath = "\(NSHomeDirectory())/Library/Messages/chat.db"
        let url = URL(fileURLWithPath: chatDBPath)
        do {
            _ = try Data(contentsOf: url, options: .alwaysMapped)
            return true
        } catch {
            return false
        }
    }
}
