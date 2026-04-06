import Foundation
import SwiftUI

// MARK: - Validation State

enum ValidationState: Equatable {
    case idle
    case validating
    case success(message: String)
    case error(message: String)
}

// MARK: - Setup Wizard ViewModel

@MainActor
@Observable
final class SetupWizardViewModel {

    // MARK: - State

    let component: Component
    let setupFlow: SetupFlow

    var currentStepIndex = 0
    var collectedInputs: [String: String] = [:]
    var validationState: ValidationState = .idle
    var currentInputValue = ""
    var isInstalling = false
    var installComplete = false

    // MARK: - Dependencies

    private let validationService = SetupValidationService()

    // MARK: - Computed

    var currentStep: SetupStep {
        setupFlow.steps[currentStepIndex]
    }

    var totalSteps: Int {
        setupFlow.steps.count
    }

    var progress: Double {
        Double(currentStepIndex + 1) / Double(totalSteps)
    }

    var canAdvance: Bool {
        switch currentStep.type {
        case .instruction:
            return true
        case .textInput, .secureInput:
            return !currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && validationState != .validating
                && localValidationPasses
        case .multiChoice:
            return !currentInputValue.isEmpty
        case .completion:
            return true
        }
    }

    var canGoBack: Bool {
        currentStepIndex > 0
    }

    var isLastStep: Bool {
        currentStepIndex == totalSteps - 1
    }

    /// Resolves {{user_input:FIELD}} placeholders in the step body text.
    var resolvedBody: String {
        resolvePlaceholders(in: currentStep.body)
    }

    /// Resolves {{user_input:FIELD}} placeholders in the step title.
    var resolvedTitle: String {
        resolvePlaceholders(in: currentStep.title)
    }

    // MARK: - Init

    init(component: Component) {
        self.component = component
        self.setupFlow = component.setupFlow!
    }

    // MARK: - Actions

    func advance() {
        // Store the current input if this step collects one
        if let config = currentStep.inputConfig {
            collectedInputs[config.fieldName] = currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard currentStepIndex < totalSteps - 1 else { return }

        currentStepIndex += 1
        validationState = .idle

        // Pre-populate input if we already have a value for this step
        if let config = currentStep.inputConfig,
           let existing = collectedInputs[config.fieldName] {
            currentInputValue = existing
        } else {
            currentInputValue = ""
        }
    }

    func goBack() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
        validationState = .idle

        // Restore the input value for this step
        if let config = currentStep.inputConfig,
           let existing = collectedInputs[config.fieldName] {
            currentInputValue = existing
        } else {
            currentInputValue = ""
        }
    }

    func validateCurrentStep() async {
        guard let config = currentStep.inputConfig,
              let action = config.validateAction else { return }

        validationState = .validating
        let value = currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch action.type {
            case .notionToken:
                let ownerName = try await validationService.validateNotionToken(value)
                validationState = .success(message: "Connected as \(ownerName)")
            case .httpGet:
                // Future: generic HTTP endpoint validation
                validationState = .success(message: "Valid")
            case .custom:
                validationState = .success(message: "Valid")
            }
        } catch {
            validationState = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Private

    private var localValidationPasses: Bool {
        guard let config = currentStep.inputConfig,
              let validation = config.validation else { return true }

        let value = currentInputValue.trimmingCharacters(in: .whitespacesAndNewlines)

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

    private func resolvePlaceholders(in text: String) -> String {
        var resolved = text
        for (key, value) in collectedInputs {
            resolved = resolved.replacingOccurrences(of: "{{user_input:\(key)}}", with: value)
        }
        return resolved
    }
}
