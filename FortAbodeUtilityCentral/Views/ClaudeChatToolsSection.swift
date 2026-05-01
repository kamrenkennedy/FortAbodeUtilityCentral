import SwiftUI
import AlignedDesignSystem

// MARK: - Claude Chat Tools — Settings section (Phase 5c.3)
//
// Editable allowlist surfaced when `permissionMode == .allowlist` (or
// `.preview` followed by Execute). Each row toggles a built-in Claude tool;
// the advanced text field accepts comma-separated patterns with selector
// syntax (e.g. `Bash(git *)` or `Edit(*.swift)`) for users who want
// fine-grained control beyond the standard set.
//
// Sits in `SettingsView` after `WeeklyRhythmEngineSection`.

struct ClaudeChatToolsSection: View {

    @Environment(ClaudeChatStore.self) private var store

    /// Local mirror of the advanced-pattern text field. Synced to
    /// `store.allowedTools` on commit so we don't write to the store on
    /// every keystroke.
    @State private var advancedText: String = ""
    @State private var advancedDirty: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Claude Chat")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    introRow
                    RowSeparator()

                    ForEach(Self.commonTools.indices, id: \.self) { idx in
                        if idx > 0 { RowSeparator() }
                        toolRow(Self.commonTools[idx])
                    }

                    RowSeparator()
                    advancedRow
                    RowSeparator()
                    actionsRow
                }
            }
        }
        .onAppear {
            advancedText = currentAdvancedPatterns().joined(separator: ", ")
            advancedDirty = false
        }
    }

    // MARK: - Rows

    private var introRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Allowed tools")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text("When the chat composer's mode pill is set to **Allowlist** (or after **Execute** on a Plan Card), Claude can use only the tools you've checked here. Off and Preview ignore this list; All bypasses it.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
        }
        .padding(.vertical, Space.s4)
    }

    private func toolRow(_ tool: CommonTool) -> some View {
        let binding = Binding<Bool>(
            get: { store.allowedTools.contains(tool.name) },
            set: { isOn in
                var current = store.allowedTools
                if isOn {
                    if !current.contains(tool.name) { current.append(tool.name) }
                } else {
                    current.removeAll { $0 == tool.name }
                }
                store.allowedTools = current
            }
        )
        return HStack(alignment: .top, spacing: Space.s4) {
            Image(systemName: tool.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Text(tool.name)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    riskBadge(tool.risk)
                }
                Text(tool.summary)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, Space.s4)
    }

    private var advancedRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Advanced patterns")
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text("Comma-separated tool patterns with selector syntax. Example: `Bash(git *)` allows only git subcommands. Added on top of the toggles above.")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Space.s2) {
                    TextField("Bash(git *), Edit(*.swift)", text: $advancedText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.bodySM)
                        .lineLimit(1...3)
                        .onChange(of: advancedText) { _, _ in advancedDirty = true }
                        .onSubmit { commitAdvancedPatterns() }

                    if advancedDirty {
                        Button("Apply", action: commitAdvancedPatterns)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s4)
    }

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            Spacer()
            Button("Reset to defaults") {
                store.allowedTools = ClaudeChatStore.defaultAllowedTools
                advancedText = ""
                advancedDirty = false
            }
            .buttonStyle(.plain)
            .font(.bodySM)
            .foregroundStyle(Color.tertiary)
        }
        .padding(.vertical, Space.s4)
    }

    // MARK: - Helpers

    private func riskBadge(_ risk: RiskLevel) -> some View {
        Text(risk.label)
            .font(.labelSM)
            .foregroundStyle(risk.color)
            .padding(.horizontal, Space.s1_5)
            .padding(.vertical, 1)
            .overlay(
                Capsule().stroke(risk.color.opacity(0.4), lineWidth: 1)
            )
    }

    private func currentAdvancedPatterns() -> [String] {
        let knownNames = Set(Self.commonTools.map(\.name))
        return store.allowedTools.filter { !knownNames.contains($0) }
    }

    private func commitAdvancedPatterns() {
        let knownNames = Set(Self.commonTools.map(\.name))
        let kept = store.allowedTools.filter { knownNames.contains($0) }
        let parsed = advancedText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var merged = kept
        for pattern in parsed where !merged.contains(pattern) {
            merged.append(pattern)
        }
        store.allowedTools = merged
        advancedDirty = false
    }

    // MARK: - Static catalog

    fileprivate struct CommonTool {
        let name: String
        let summary: String
        let icon: String
        let risk: RiskLevel
    }

    fileprivate enum RiskLevel {
        case low, medium, high

        var label: String {
            switch self {
            case .low: return "low risk"
            case .medium: return "med risk"
            case .high: return "high risk"
            }
        }
        var color: Color {
            switch self {
            case .low: return Color.onSurfaceVariant
            case .medium: return Color.tertiary
            case .high: return Color.brandRust
            }
        }
    }

    fileprivate static let commonTools: [CommonTool] = [
        CommonTool(name: "Read", summary: "Read files from your machine.",
                   icon: "doc.text", risk: .low),
        CommonTool(name: "Grep", summary: "Search file contents by regex.",
                   icon: "magnifyingglass", risk: .low),
        CommonTool(name: "Glob", summary: "Find files by name pattern.",
                   icon: "folder.badge.questionmark", risk: .low),
        CommonTool(name: "Edit", summary: "Modify existing files.",
                   icon: "pencil", risk: .medium),
        CommonTool(name: "Write", summary: "Create new files.",
                   icon: "doc.badge.plus", risk: .medium),
        CommonTool(name: "WebFetch", summary: "Download a URL's contents.",
                   icon: "globe", risk: .medium),
        CommonTool(name: "WebSearch", summary: "Search the web for information.",
                   icon: "magnifyingglass.circle", risk: .low),
        CommonTool(name: "Bash", summary: "Run shell commands. Powerful and irreversible — leave off unless you trust the prompt.",
                   icon: "terminal", risk: .high)
    ]
}
