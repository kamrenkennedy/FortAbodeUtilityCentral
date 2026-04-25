import SwiftUI
import AppKit
import AlignedDesignSystem

// MARK: - Feedback View
//
// v4.0.0 restyle. Presented as a sheet from Settings → Send Feedback OR from
// the chat panel's "Report a bug" suggestion chip. Preserves the existing
// FeedbackViewModel + FeedbackService flow (writes structured reports to the
// shared iCloud folder — zero Claude API tokens for what is fundamentally a
// form post). Only the visuals are new.

struct FeedbackView: View {

    @Environment(ComponentListViewModel.self) private var listViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FeedbackViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Fort Abode", title: "Send Feedback")

                VStack(alignment: .leading, spacing: Space.s5) {
                    typeRow
                    if viewModel.feedbackType == .bug {
                        componentRow
                    }
                    GhostBorderField(
                        label: "Subject",
                        text: $viewModel.subject,
                        placeholder: "Brief summary"
                    )
                    detailsField

                    if viewModel.feedbackType == .bug {
                        debugReportChip
                    }

                    if let result = viewModel.submitResult {
                        resultBanner(result)
                    }

                    submitRow
                }
                .padding(.horizontal, Space.s16)
                .padding(.bottom, Space.s24)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            await viewModel.checkConfiguration()
        }
    }

    // MARK: - Type segmented picker

    private var typeRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Type".uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)

            let binding = Binding<FeedbackType>(
                get: { viewModel.feedbackType },
                set: { viewModel.feedbackType = $0 }
            )

            SegmentedTabBar(
                options: FeedbackType.allCases,
                selection: binding,
                label: { $0.rawValue }
            )
        }
    }

    // MARK: - Component picker (bug only)

    private var componentRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Component".uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)

            Picker("", selection: $viewModel.selectedComponentId) {
                Text("General / Not sure").tag(nil as String?)
                ForEach(listViewModel.installedComponents) { component in
                    Text(component.displayName).tag(component.id as String?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - Details field

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Details".uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)

            TextEditor(text: $viewModel.descriptionText)
                .font(.bodyLG)
                .foregroundStyle(Color.onSurface)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(Space.s2)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.surfaceContainerLow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.outlineVariant.opacity(0.4), lineWidth: 1)
                )
        }
    }

    // MARK: - Debug report chip

    private var debugReportChip: some View {
        HStack(spacing: Space.s1_5) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 11, weight: .medium))
            Text("A debug report will be included automatically")
                .font(.labelMD)
        }
        .foregroundStyle(Color.onTertiaryContainer)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1_5)
        .background(
            Capsule()
                .fill(Color.tertiaryContainer)
        )
    }

    // MARK: - Submit row

    private var submitRow: some View {
        HStack {
            Spacer()

            Button {
                Task {
                    await viewModel.submit(
                        statuses: listViewModel.statuses,
                        components: listViewModel.components
                    )
                }
            } label: {
                HStack(spacing: Space.s2) {
                    if viewModel.isSubmitting {
                        ProgressView().controlSize(.small)
                            .tint(Color.onPrimary)
                    }
                    Text(viewModel.isSubmitting ? "Submitting…" : "Submit")
                        .font(.labelLG.weight(.semibold))
                }
                .foregroundStyle(Color.onPrimary)
                .padding(.horizontal, Space.s5)
                .padding(.vertical, Space.s3)
                .background(
                    Capsule()
                        .fill(Color.primaryFill)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitDisabled)
            .opacity(isSubmitDisabled ? 0.5 : 1)
            .ctaShadow()
        }
    }

    private var isSubmitDisabled: Bool {
        viewModel.isSubmitting ||
        viewModel.subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Result banner

    @ViewBuilder
    private func resultBanner(_ result: FeedbackViewModel.SubmitResult) -> some View {
        switch result {
        case .success(let savedPath):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusScheduled)
                        .font(.system(size: 14))
                    Text("Feedback saved — Kam will pick it up from iCloud")
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                }

                HStack(spacing: Space.s2) {
                    Text(savedPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: Space.s2)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(savedPath, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                    .help("Copy file path to clipboard")
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.statusScheduled.opacity(0.12))
            )

        case .error(let message):
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.statusError)
                    .font(.system(size: 14))
                Text(message)
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurface)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.statusError.opacity(0.12))
            )
        }
    }
}
