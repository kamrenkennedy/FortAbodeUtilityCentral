import SwiftUI
import AlignedDesignSystem

/// Apple Setup Assistant-style wizard for configuring components that require user input.
/// Presented as a 540x480 sheet from MarketplaceView or ComponentDetailView.
struct SetupWizardView: View {
    @Bindable var viewModel: SetupWizardViewModel
    let onComplete: ([String: String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Cancel button + progress bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 8)
                .help("Cancel")

                Spacer()
            }

            progressBar

            // Step content
            ScrollView {
                stepContent
                    .id(viewModel.currentStepIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation bar
            navigationBar
        }
        .frame(width: 540, height: 480)
        .background(Color.surface.ignoresSafeArea())
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)

                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 16)

            // Illustration
            StepIllustrationView(illustration: viewModel.currentStep.illustration)

            // Title
            Text(viewModel.resolvedTitle)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Subtitle
            if let subtitle = viewModel.currentStep.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Body
            Text(viewModel.resolvedBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)

            // Input area (type-dependent)
            StepContentView(viewModel: viewModel)
                .offset(x: shakeOffset)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.goBack()
                }
            }
            .disabled(!viewModel.canGoBack)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Spacer()

            // External URL button (if applicable)
            if let urlString = viewModel.currentStep.externalUrl,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            // Action button
            if viewModel.isLastStep {
                installButton
            } else {
                Button(viewModel.currentStep.actionLabel) {
                    handleAdvance()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(!viewModel.canAdvance)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Install Button

    private var installButton: some View {
        Button {
            viewModel.advance() // Store final step's inputs
            onComplete(viewModel.collectedInputs)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                if viewModel.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.currentStep.actionLabel)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(viewModel.isInstalling)
        .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: - Actions

    private func handleAdvance() {
        // For secure inputs that need remote validation and haven't been validated yet
        if viewModel.currentStep.type == .secureInput,
           viewModel.currentStep.inputConfig?.validateAction != nil,
           case .idle = viewModel.validationState {
            // Shake to indicate they should validate first
            triggerShake()
            return
        }

        if viewModel.currentStep.type == .secureInput,
           case .error = viewModel.validationState {
            triggerShake()
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.advance()
        }
    }

    private func triggerShake() {
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shakeOffset = 0
        }
    }
}
