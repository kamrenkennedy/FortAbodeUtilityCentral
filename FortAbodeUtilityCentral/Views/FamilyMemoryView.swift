import SwiftUI
import AppKit
import AlignedDesignSystem

// MARK: - Family Memory View (sidebar hub)
//
// The "Family" tab. NavigationSplitView with a left-nav of sections parsed
// from FAMILY_MEMORY.md plus a synthetic "Status" entry. Health is the only
// section with a custom dashboard today; everything else falls back to a
// markdown-preview / empty-state view driven by the section body.

struct FamilyMemoryView: View {

    @State private var facts: FamilyFacts?
    @State private var sections: [FamilySection] = []
    @State private var lastModified: String?
    @State private var healthChecks: [HealthCheck] = []
    @State private var selection: SidebarItem = .health
    @State private var isLoading = true

    private let service = FamilyMemoryService()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .navigationTitle("Family Memory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    FamilyMemoryService.revealInFinder(path: FamilyMemoryService.folderPath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            Section("Dashboards") {
                sidebarRow(
                    icon: "heart.fill",
                    color: .pink,
                    label: "Health",
                    subtitle: facts?.insurance?.health?.first?.monthlyPremium
                )
                .tag(SidebarItem.health)
            }

            Section("Sections") {
                ForEach(contentSections) { section in
                    sidebarRow(
                        icon: iconForSection(section.name),
                        color: .secondary,
                        label: section.name,
                        subtitle: section.isEmpty ? "No facts yet" : nil,
                        isDimmed: section.isEmpty
                    )
                    .tag(SidebarItem.markdownSection(section.id))
                }
            }

            Section("System") {
                sidebarRow(
                    icon: "checkmark.seal.fill",
                    color: statusTint,
                    label: "Status",
                    subtitle: lastModified.map { "Updated \($0)" }
                )
                .tag(SidebarItem.status)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarRow(icon: String, color: Color, label: String, subtitle: String? = nil, isDimmed: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if isLoading {
            ProgressView("Loading family memory…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selection {
            case .health:
                healthDetail
            case .markdownSection(let id):
                markdownSectionDetail(id)
            case .status:
                statusDetail
            }
        }
    }

    @ViewBuilder
    private var healthDetail: some View {
        if let plan = facts?.insurance?.health?.first {
            FamilyHealthDashboard(plan: plan)
        } else {
            emptyState(
                icon: "heart.text.square",
                title: "No health plan recorded",
                detail: "Once health insurance facts land in FAMILY_MEMORY.md and facts.json, this page will render the full plan breakdown."
            )
        }
    }

    @ViewBuilder
    private func markdownSectionDetail(_ id: String) -> some View {
        if let section = sections.first(where: { $0.id == id }) {
            if section.isEmpty {
                emptyState(
                    icon: iconForSection(section.name),
                    title: "\(section.name) is empty",
                    detail: "Add facts to FAMILY_MEMORY.md and they'll appear here. Open the file in Finder to edit."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.name)
                            .font(.title2.bold())
                        Text(section.body)
                            .font(.body.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            emptyState(
                icon: "doc.text",
                title: "Section not found",
                detail: "FAMILY_MEMORY.md may not include this section yet."
            )
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Family Memory Status")
                    .font(.title2.bold())

                Text("Checks whether the shared iCloud folder, key data files, and Claude routing block are all in place. All four rows should be green on a healthy install.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ComponentHealthCard(checks: healthChecks)

                if let modified = lastModified {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Last modified: \(modified)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                Button {
                    FamilyMemoryService.revealInFinder(path: FamilyMemoryService.folderPath)
                } label: {
                    Label("Open Family Memory folder in Finder", systemImage: "folder")
                }
                .buttonStyle(.alignedSecondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Button {
                FamilyMemoryService.revealInFinder(path: FamilyMemoryService.folderPath)
            } label: {
                Label("Open folder in Finder", systemImage: "folder")
            }
            .buttonStyle(.alignedSecondary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func load() async {
        let loadedFacts = await service.loadFacts()
        let loadedSections = await service.loadSections()
        let loadedModified = await service.loadLastModified()
        let loadedHealth = await service.healthChecks()

        facts = loadedFacts
        sections = loadedSections
        lastModified = loadedModified
        healthChecks = loadedHealth
        isLoading = false
    }

    // MARK: - Helpers

    /// Sections that render as nav rows (Health is a dedicated dashboard, so
    /// skip it here; Open Questions / To Discuss is always shown; empty ones
    /// are dimmed but still visible so the structure is legible).
    private var contentSections: [FamilySection] {
        sections.filter { section in
            let name = section.name.lowercased()
            return !name.contains("insurance") // replaced by Health dashboard
        }
    }

    private func iconForSection(_ name: String) -> String {
        switch name.lowercased() {
        case let n where n.contains("household"): return "house.fill"
        case let n where n.contains("house"): return "house"
        case let n where n.contains("vehicle"): return "car.fill"
        case let n where n.contains("finance"): return "dollarsign.circle.fill"
        case let n where n.contains("contact"): return "person.2.fill"
        case let n where n.contains("travel"): return "airplane"
        case let n where n.contains("calendar"): return "calendar"
        case let n where n.contains("wedding"), let n where n.contains("anniversary"): return "heart.square.fill"
        case let n where n.contains("open questions"), let n where n.contains("discuss"): return "questionmark.bubble"
        default: return "doc.text"
        }
    }

    private var statusTint: Color {
        let allGreen = healthChecks.allSatisfy { $0.state == .granted }
        return allGreen ? .green : .orange
    }
}

// MARK: - Sidebar selection

enum SidebarItem: Hashable {
    case health
    case markdownSection(String)
    case status
}
