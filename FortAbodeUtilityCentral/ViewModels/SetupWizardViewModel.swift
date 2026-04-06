import Foundation
import SwiftUI

// MARK: - Validation State

enum CommandRunState: Equatable {
    case idle
    case running
    case success
    case error(message: String)
}

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

    /// State for run_command steps
    var commandState: CommandRunState = .idle
    var commandOutput = ""

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
        case .runCommand:
            return commandState == .success
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
        commandState = .idle
        commandOutput = ""

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
        commandState = .idle
        commandOutput = ""

        // Restore the input value for this step
        if let config = currentStep.inputConfig,
           let existing = collectedInputs[config.fieldName] {
            currentInputValue = existing
        } else {
            currentInputValue = ""
        }
    }

    /// Run the shell command defined in the current step's runConfig.
    func runCurrentCommand() async {
        guard let config = currentStep.runConfig else { return }

        commandState = .running
        commandOutput = ""

        // If globalInstall is specified, install it first
        if let package = config.globalInstall {
            let installResult = await runProcess(
                command: "/usr/bin/env",
                args: ["npm", "install", "-g", package],
                env: nil
            )
            if !installResult.success {
                commandState = .error(message: "Failed to install \(package): \(installResult.output)")
                return
            }
        }

        // Resolve placeholders in args and env
        let resolvedArgs = config.args.map { resolvePlaceholders(in: $0) }
        let resolvedEnv = config.env?.mapValues { resolvePlaceholders(in: $0) }

        // Find the command path
        let commandPath = await findCommandPath(config.command)

        let result = await runProcess(
            command: commandPath ?? config.command,
            args: resolvedArgs,
            env: resolvedEnv
        )

        if result.success {
            commandState = .success
            commandOutput = config.successMessage
        } else {
            commandState = .error(message: result.output.isEmpty ? "Command failed" : String(result.output.prefix(200)))
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
        // Resolve {{resolved:CONFIG_DIR}} for Google Workspace
        if let accountName = collectedInputs["ACCOUNT_NAME"] {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let configDir = "\(home)/.config/gws-\(accountName)"
            resolved = resolved.replacingOccurrences(of: "{{resolved:CONFIG_DIR}}", with: configDir)
        }
        return resolved
    }

    // MARK: - Process Execution

    private struct ProcessResult {
        let success: Bool
        let output: String
    }

    private func runProcess(command: String, args: [String], env: [String: String]?) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = pipe

                // Inherit PATH from login shell and add custom env
                var environment = ProcessInfo.processInfo.environment
                if let env {
                    for (key, value) in env {
                        environment[key] = value
                    }
                }
                process.environment = environment

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    continuation.resume(returning: ProcessResult(
                        success: process.terminationStatus == 0,
                        output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                } catch {
                    continuation.resume(returning: ProcessResult(
                        success: false,
                        output: error.localizedDescription
                    ))
                }
            }
        }
    }

    private func findCommandPath(_ command: String) async -> String? {
        let result = await runProcess(
            command: "/bin/zsh",
            args: ["-l", "-c", "which \(command)"],
            env: nil
        )
        return result.success ? result.output : nil
    }
}
