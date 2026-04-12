import SwiftUI

// MARK: - Feedback View

struct FeedbackView: View {

    @Environment(ComponentListViewModel.self) private var listViewModel
    @State private var viewModel = FeedbackViewModel()

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            Group {
                if !viewModel.isConfigured {
                    notConfiguredView
                } else {
                    feedbackForm
                }
            }
        }
        .navigationTitle("Send Feedback")
        .task {
            await viewModel.checkConfiguration()
        }
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Feedback isn't set up yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Ask Kam to configure it on his machine, or set it up in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Feedback Form

    private var feedbackForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Type picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Type", selection: $viewModel.feedbackType) {
                        ForEach(FeedbackType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Component picker (bugs only)
                if viewModel.feedbackType == .bug {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Component")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Component", selection: $viewModel.selectedComponentId) {
                            Text("General / Not sure").tag(nil as String?)
                            ForEach(listViewModel.installedComponents) { component in
                                Text(component.displayName).tag(component.id as String?)
                            }
                        }
                    }
                }

                // Subject
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subject")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Brief summary", text: $viewModel.subject)
                        .textFieldStyle(.roundedBorder)
                }

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Details")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $viewModel.descriptionText)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                        .scrollContentBackground(.hidden)
                }

                // Debug report badge
                if viewModel.feedbackType == .bug {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("A debug report will be included automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                // Result banner
                if let result = viewModel.submitResult {
                    resultBanner(result)
                }

                // Submit button
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
                        if viewModel.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Submit")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isSubmitting || viewModel.subject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(32)
        }
    }

    // MARK: - Result Banner

    @ViewBuilder
    private func resultBanner(_ result: FeedbackViewModel.SubmitResult) -> some View {
        switch result {
        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Feedback submitted — thank you!")
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
