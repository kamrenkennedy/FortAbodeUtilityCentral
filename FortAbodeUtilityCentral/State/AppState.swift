import SwiftUI
import Observation

// Top-level UI state for the v4.0.0 shell.
//
// - `selectedDestination` drives the sidebar tab.
// - `sidebarCollapsed` and `theme` persist to UserDefaults under the same keys
//   the HTML mockup uses (`fa-sidebar-collapsed`, `fa-theme`) so the redesigned
//   prototype's interaction notes apply 1:1 here.
// - Chat panel state lives here so the FAB, panel, and any page that needs
//   page-aware context (e.g. ClaudeChatPane's "Fort Abode · {page}" pill) read
//   from a single source.
// - `feedbackSheetOpen` drives the existing FeedbackView as a sheet — opened
//   from Settings → Send Feedback OR from the chat panel's "Report a bug"
//   suggestion chip. Keeps bug reports flowing through FeedbackService's
//   structured iCloud submission instead of burning Claude API tokens.

@MainActor
@Observable
final class AppState {

    var selectedDestination: Destination = .home

    var sidebarCollapsed: Bool {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed) }
    }

    var theme: ThemePref {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    var chatPanelOpen: Bool = false
    var chatPanelExpanded: Bool = false

    var chatActiveTab: ChatTab = .family {
        didSet {
            if chatActiveTab == .family && oldValue != .family {
                unreadFamilyCount = 0
            }
        }
    }

    var unreadFamilyCount: Int = 2
    var feedbackSheetOpen: Bool = false

    init() {
        sidebarCollapsed = UserDefaults.standard.bool(forKey: Keys.sidebarCollapsed)
        let rawTheme = UserDefaults.standard.string(forKey: Keys.theme) ?? ThemePref.dark.rawValue
        theme = ThemePref(rawValue: rawTheme) ?? .dark
    }

    func openChat(_ tab: ChatTab) {
        chatActiveTab = tab
        chatPanelOpen = true
        if tab == .family {
            unreadFamilyCount = 0
        }
    }

    func closeChat() {
        chatPanelOpen = false
        chatPanelExpanded = false
    }

    private enum Keys {
        static let sidebarCollapsed = "fa-sidebar-collapsed"
        static let theme            = "fa-theme"
    }
}

enum ThemePref: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

enum ChatTab: String, CaseIterable, Identifiable {
    case family, claude

    var id: Self { self }

    var label: String {
        switch self {
        case .family: return "Family"
        case .claude: return "Claude"
        }
    }
}
