import SwiftUI
import AlignedDesignSystem

// Marketplace — v4.0.0 unified extensions hub. Editorial header with a
// trailing Check All CTA, optional Updates Available banner (when any
// component has an update ready), Installed bento grid, then Browse bento
// grid for not-yet-installed marketplace items. Tapping a card pushes to
// ComponentDetailView via the parent NavigationStack's AppDestination route.

struct MarketplaceView: View {

    @Environment(ComponentListViewModel.self) private var viewModel
    @Environment(AppState.self) private var appState
    @State private var wizardComponent: Component?

    // Fixed-column grid driven by `appState.marketplaceColumns`. Switching the
    // toggle reflows both Installed and Browse grids (UPDATE-2026-04-26-desktop-mac.md §2).
    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Space.s3),
            count: appState.marketplaceColumns.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorialHeader

                VStack(alignment: .leading, spacing: Space.s8) {
                    if hasUpdatesAvailable {
                        updatesBanner
                    }
                    installedSection
                    if !viewModel.marketplaceItems.isEmpty {
                        browseSection
                    }
                }
                .padding(.horizontal, Space.s10)
                .padding(.bottom, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $wizardComponent) { component in
            SetupWizardView(
                viewModel: SetupWizardViewModel(component: component),
                onComplete: { inputs in
                    Task { await viewModel.installComponentWithInputs(component.id, inputs: inputs) }
                }
            )
        }
        .task {
            await viewModel.checkAll()
        }
    }

    // MARK: - Editorial header with trailing CTA

    private var editorialHeader: some View {
        HStack(alignment: .bottom, spacing: Space.s8) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Extensions".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Text("Marketplace")
                    .font(.displayLG)
                    .foregroundStyle(Color.onSurface)
                    .kerning(-1.0)
            }

            Spacer(minLength: Space.s4)

            CheckAllButton(isChecking: viewModel.isCheckingAll) {
                Task { await viewModel.checkAll() }
            }
            .padding(.bottom, Space.s2)
        }
        .padding(.top, Space.s16)
        .padding(.horizontal, Space.s10)
        .padding(.bottom, Space.s16)
    }

    // MARK: - Updates banner

    private var hasUpdatesAvailable: Bool {
        viewModel.availableUpdateCount > 0
    }

    private var updatesBanner: some View {
        UpdatesBanner(
            count: viewModel.availableUpdateCount,
            summary: updatesSummary,
            onInstallAll: {
                Task { await viewModel.updateAll() }
            }
        )
    }

    private var updatesSummary: String {
        let updates = viewModel.installedComponents.compactMap { component -> String? in
            if case .updateAvailable(let installed, let latest) = viewModel.statuses[component.id] {
                return "\(component.displayName) v\(installed) → v\(latest)"
            }
            return nil
        }
        return updates.prefix(2).joined(separator: " · ")
    }

    // MARK: - Installed

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("Installed".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text(installedFooter)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                marketplaceColumnsControl
            }

            if viewModel.installedComponents.isEmpty {
                emptyInstalled
            } else {
                LazyVGrid(columns: gridColumns, spacing: Space.s3) {
                    ForEach(viewModel.installedComponents) { component in
                        NavigationLink(value: AppDestination.componentDetail(componentId: component.id)) {
                            BentoCard(
                                component: component,
                                status: viewModel.statuses[component.id] ?? .unknown,
                                showsBrowseInstall: false,
                                onInstall: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Tiny 2up/3up toggle, top-right of Installed section per
    // UPDATE-2026-04-26-desktop-mac.md §2.
    private var marketplaceColumnsControl: some View {
        let binding = Binding<MarketplaceColumns>(
            get: { appState.marketplaceColumns },
            set: { appState.marketplaceColumns = $0 }
        )
        return SegmentedTabBar(
            options: MarketplaceColumns.allCases,
            selection: binding,
            label: { $0.label },
            trailingAccessory: { _ in AnyView(EmptyView()) }
        )
    }

    private var installedFooter: String {
        let count = viewModel.installedComponents.count
        let extensionsLabel = "\(count) extension\(count == 1 ? "" : "s")"
        if let lastChecked = viewModel.lastCheckedText.nilIfEmpty {
            return "\(extensionsLabel) · \(lastChecked.lowercased())"
        }
        return extensionsLabel
    }

    private var emptyInstalled: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.onSurfaceVariant)
            Text("No extensions installed")
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
            Text("Browse the Marketplace below to install your first extension.")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(Space.s8)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color.cardBackground)
        )
        .whisperShadow()
    }

    // MARK: - Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Browse".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text("\(viewModel.marketplaceItems.count) available")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            LazyVGrid(columns: gridColumns, spacing: Space.s3) {
                ForEach(viewModel.marketplaceItems) { component in
                    NavigationLink(value: AppDestination.componentDetail(componentId: component.id)) {
                        BentoCard(
                            component: component,
                            status: viewModel.statuses[component.id] ?? .notInstalled,
                            showsBrowseInstall: true,
                            onInstall: {
                                if component.requiresSetup {
                                    wizardComponent = component
                                } else {
                                    Task { await viewModel.installComponent(component.id) }
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Check All button

private struct CheckAllButton: View {
    let isChecking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.surface)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                }
                Text("Check All")
            }
        }
        .buttonStyle(.alignedPrimary)
        .disabled(isChecking)
        .opacity(isChecking ? 0.7 : 1)
    }
}

// MARK: - Updates banner

// Marketplace updates banner per UPDATE-2026-04-25.md §2b. The left-edge accent
// strip from the prior version is intentionally removed — the warm-amber underglow
// beneath the card now carries the visual weight. Gradient bg blends from the
// neutral card surface (top) to a 4–5% warm-amber tint (bottom) so the glow reads
// as light leaking out rather than a colored card.
private struct UpdatesBanner: View {
    let count: Int
    let summary: String
    let onInstallAll: () -> Void

    var body: some View {
        HStack(spacing: Space.s5) {
            HStack(spacing: Space.s5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.warmAmber)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Color.warmAmber.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Updates Available".uppercased())
                        .font(.labelSM)
                        .tracking(1.5)
                        .foregroundStyle(Color.secondaryText)
                    Text("\(count) extension\(count == 1 ? "" : "s") have updates ready")
                        .font(.headlineMD)
                        .foregroundStyle(Color.onSurface)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.bodySM)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .padding(.top, 2)
                    }
                }
            }

            Spacer(minLength: Space.s4)

            Button(action: onInstallAll) {
                HStack(spacing: 6) {
                    Text("Install all updates")
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.alignedPrimary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cardBackground,
                            Color(light: 0xFDFAF7, dark: 0x2C2925)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .whisperShadow()
        .warmAmberUnderglow()
    }
}

// MARK: - Bento card

private struct BentoCard: View {
    let component: Component
    let status: UpdateStatus
    let showsBrowseInstall: Bool
    let onInstall: (() -> Void)?

    @State private var isHovering = false

    // BentoCard desktop sizing per UPDATE-2026-04-26-desktop-mac.md:
    //   • padding 18pt, radius 14pt (Radius.xl2 desktop), min-height 132pt
    //   • inner gap 8pt, mcp-icon 28×28 r6 (Radius.md desktop)
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                iconBadge
                Spacer(minLength: Space.s2)
                statusDot
            }

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(component.displayName)
                    .font(.headlineSM)
                    .foregroundStyle(Color.onSurface)
                    .lineLimit(1)

                Text(component.userDescription ?? component.description)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            footerRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl2, style: .continuous)
                .fill(Color.cardBackground)
        )
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .whisperShadow()
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var iconBadge: some View {
        Image(systemName: component.iconName)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.onSurfaceVariant)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.surfaceContainerHigh)
            )
    }

    @ViewBuilder
    private var statusDot: some View {
        switch status {
        case .upToDate, .updateComplete: StatusDot(.scheduled)
        case .updateAvailable:           StatusDot(.draft)
        case .error, .checkFailed:       StatusDot(.error)
        case .updating, .checking:       StatusDot(.neutral)
        case .notInstalled:              EmptyView()
        case .unknown:                   StatusDot(.neutral)
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        switch status {
        case .upToDate(let version):
            footerText("v\(version) · up to date")
        case .updateAvailable(let installed, let latest):
            HStack(spacing: Space.s2) {
                Text("v\(installed) → v\(latest)")
                    .font(.bodySM)
                    .foregroundStyle(Color.statusDraft)
                Spacer(minLength: Space.s2)
                MiniCTAButton(label: "Update") {
                    // Update flow surfaces from detail view in v4.0.0;
                    // tap drills into the card.
                }
            }
        case .error(let msg):
            HStack(spacing: Space.s2) {
                Text(msg)
                    .font(.bodySM)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                MiniCTAButton(label: "Re-auth") {}
            }
        case .updating:
            HStack(spacing: Space.s2) {
                ProgressView().controlSize(.small)
                Text("Updating…")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        case .checking:
            footerText("checking…")
        case .updateComplete(let version):
            footerText("v\(version) · just updated")
        case .checkFailed(let version):
            footerText("v\(version) · couldn't check")
        case .notInstalled:
            if showsBrowseInstall, let onInstall {
                HStack {
                    Text("Not installed")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                    Spacer(minLength: Space.s2)
                    MiniCTAButton(label: "Install", action: onInstall)
                }
            } else {
                footerText("Not installed")
            }
        case .unknown:
            footerText("status unknown")
        }
    }

    private func footerText(_ text: String) -> some View {
        Text(text)
            .font(.bodySM)
            .foregroundStyle(Color.onSurfaceVariant)
    }
}

// MiniCTAButton — used inline on per-card footers (Update / Re-auth / Install).
// Maps to `.alignedPrimaryMini` per UPDATE-2026-04-25.md mini-variant spec.
private struct MiniCTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(.alignedPrimaryMini)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
