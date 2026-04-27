import SwiftUI
import AlignedDesignSystem

// MARK: - RunHealthDetailSheet
//
// Surface 5 from the parity-pass design package — Run Health detail modal.
// Tapping the RunHealthPill opens this view. Shows the engine's most recent
// run report: MCP health, last run metadata, recent errors.
//
// Spec: .claude/design/v4-parity-pass/README.md §5
//
// Width 620pt. Header trailing badge: "All good" (statusScheduled) or
// "Issues detected" (brandRust). Body sections separated by Space.s6.
// Mono typography for versions / durations / error timestamps.

struct RunHealthDetailSheet: View {
    let report: RunReport
    let runHealth: RunHealth
    let onDismiss: () -> Void

    @State private var errorsExpanded = false

    var body: some View {
        AlignedSheet(
            eyebrow: "Run Health",
            title: "Engine status",
            badge: AnyView(headerBadge),
            idealWidth: 620,
            onDismiss: onDismiss,
            content: { detailBody },
            footer: { footer }
        )
    }

    // MARK: - Header badge

    private var headerBadge: some View {
        let isAllGood: Bool = {
            if case .allGood = runHealth { return true }
            return false
        }()
        return Text(isAllGood ? "All good" : "Issues detected")
            .font(.labelSM.weight(.medium))
            .foregroundStyle(isAllGood ? Color.statusScheduled : Color.brandRust)
            .padding(.horizontal, Space.s2_5)
            .frame(height: 22)
            .background(
                Capsule().fill(
                    (isAllGood ? Color.statusScheduled : Color.brandRust).opacity(0.18)
                )
            )
    }

    // MARK: - Body

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            mcpHealthSection
            lastRunSection
            recentErrorsSection
        }
    }

    // MARK: - MCP health

    private var mcpHealthSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("MCP HEALTH")
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer()
                Text("\(report.mcpStatuses.count) connectors")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            VStack(spacing: 0) {
                ForEach(Array(report.mcpStatuses.enumerated()), id: \.element.id) { offset, mcp in
                    mcpRow(mcp)
                    if offset < report.mcpStatuses.count - 1 {
                        Rectangle()
                            .fill(Color.outlineVariant.opacity(0.5))
                            .frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.surfaceContainerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .stroke(Color.outlineVariant, lineWidth: 1)
                    )
            )
        }
    }

    private func mcpRow(_ mcp: MCPStatus) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            StatusDot(mcp.status.styleKind)
            Text(mcp.name)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(mcp.version)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.onSurfaceVariant)
            Text(mcp.lastSuccess)
                .font(.bodySM)
                .foregroundStyle(Color.secondaryText)
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - Last run

    private var lastRunSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LAST RUN")
                .font(.labelSM)
                .tracking(2.0)
                .foregroundStyle(Color.secondaryText)

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .topLeading),
                GridItem(.flexible(), alignment: .topLeading)
            ], spacing: Space.s4) {
                metaPair(label: "Triggered",     value: report.triggered, mono: false)
                metaPair(label: "Duration",      value: report.duration,  mono: true)
                metaPair(label: "Outcome",       value: report.outcome,   mono: false)
                metaPair(label: "Engine version",value: report.engineVersion, mono: true)
            }
        }
    }

    private func metaPair(label: String, value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label.uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .bodyMD)
                .foregroundStyle(Color.onSurface)
        }
    }

    // MARK: - Recent errors

    private var recentErrorsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RECENT ERRORS")
                .font(.labelSM)
                .tracking(2.0)
                .foregroundStyle(Color.secondaryText)

            Button {
                if !report.recentErrors.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        errorsExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: Space.s3) {
                    StatusDot(report.recentErrors.isEmpty ? .scheduled : .error)
                    Text(report.recentErrors.isEmpty
                         ? "No errors in the last 7 days"
                         : "\(report.recentErrors.count) error\(report.recentErrors.count == 1 ? "" : "s") in the last 7 days")
                        .font(.bodyMD)
                        .foregroundStyle(Color.onSurface)
                    Spacer()
                    if !report.recentErrors.isEmpty {
                        Image(systemName: errorsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(Color.outlineVariant, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if errorsExpanded && !report.recentErrors.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(report.recentErrors) { err in
                        HStack(alignment: .top, spacing: Space.s2) {
                            Text(err.timestamp)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.secondaryText)
                                .frame(width: 96, alignment: .leading)
                            Text(err.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            Text("Re-runs are queued by the engine, not the app.")
                .font(.bodySM)
                .foregroundStyle(Color.secondaryText)

            Spacer()

            Button("Close", action: onDismiss)
                .buttonStyle(.alignedPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }
}
