import SwiftUI
import AlignedDesignSystem

/// Renders the input area for a setup wizard step based on its type.
struct StepContentView: View {
    @Bindable var viewModel: SetupWizardViewModel

    var body: some View {
        switch viewModel.currentStep.type {
        case .instruction:
            EmptyView()

        case .textInput:
            textInputSection

        case .secureInput:
            secureInputSection

        case .multiChoice:
            multiChoiceSection

        case .runCommand:
            runCommandSection

        case .completion:
            completionSummary
        }
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(spacing: 8) {
            TextField(
                viewModel.currentStep.inputConfig?.placeholder ?? "",
                text: $viewModel.currentInputValue
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 300)

            if let validation = viewModel.currentStep.inputConfig?.validation,
               !viewModel.currentInputValue.isEmpty,
               !localValidationPasses(validation) {
                Text(validation.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Secure Input

    private var secureInputSection: some View {
        VStack(spacing: 12) {
            SecureField(
                viewModel.currentStep.inputConfig?.placeholder ?? "",
                text: $viewModel.currentInputValue
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 300)

            if viewModel.currentStep.inputConfig?.validateAction != nil {
                validateButton
            }

            validationMessage
        }
    }

    private var validateButton: some View {
        Button {
            Task { await viewModel.validateCurrentStep() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.validationState == .validating {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(validationButtonLabel)
            }
        }
        .disabled(viewModel.currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || viewModel.validationState == .validating)
        .buttonStyle(.alignedSecondaryMini)
    }

    private var validationButtonLabel: String {
        switch viewModel.validationState {
        case .idle: return "Validate"
        case .validating: return "Checking..."
        case .success: return "Validated"
        case .error: return "Retry"
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        switch viewModel.validationState {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .transition(.opacity)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .transition(.opacity)

        default:
            EmptyView()
        }
    }

    // MARK: - Multi Choice

    private var multiChoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let options = viewModel.currentStep.inputConfig?.options {
                ForEach(options, id: \.value) { option in
                    Button {
                        viewModel.currentInputValue = option.value
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: viewModel.currentInputValue == option.value
                                  ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(viewModel.currentInputValue == option.value ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.body)
                                if let desc = option.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Run Command

    private var runCommandSection: some View {
        VStack(spacing: 12) {
            switch viewModel.commandState {
            case .idle:
                Button {
                    Task { await viewModel.runCurrentCommand() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.alignedPrimary)

            case .running:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .success:
                Label(viewModel.commandOutput, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .transition(.opacity)

            case .error(let message):
                VStack(spacing: 8) {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: 350)

                    Button {
                        Task { await viewModel.runCurrentCommand() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.alignedSecondaryMini)
                }
            }
        }
    }

    // MARK: - Completion Summary

    private var completionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fields = viewModel.currentStep.summaryFields {
                ForEach(fields, id: \.self) { field in
                    if let value = viewModel.collectedInputs[field] {
                        HStack {
                            Text(field.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing)
                            Text(maskIfSensitive(field: field, value: value))
                                .font(.body.monospaced())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func localValidationPasses(_ validation: InputValidation) -> Bool {
        let value = viewModel.currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch validation.type {
        case .regex:
            guard let pattern = validation.pattern else { return true }
            return value.range(of: pattern, options: .regularExpression) != nil
        case .notEmpty:
            return !value.isEmpty
        case .minLength:
            return value.count >= (validation.minLength ?? 1)
        }
    }

    private func maskIfSensitive(field: String, value: String) -> String {
        let sensitiveKeywords = ["TOKEN", "SECRET", "KEY", "PASSWORD"]
        if sensitiveKeywords.contains(where: { field.uppercased().contains($0) }) {
            let prefix = String(value.prefix(8))
            return "\(prefix)..."
        }
        return value
    }
}
