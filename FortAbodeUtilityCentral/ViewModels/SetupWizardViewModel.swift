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
    /// All commands run through a login shell to inherit PATH (nvm, Homebrew, etc.)
    func runCurrentCommand() async {
        guard let config = currentStep.runConfig else { return }

        commandState = .running
        commandOutput = ""

        // Copy bundled OAuth credentials if this component uses them
        if let configDir = config.env?["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] {
            let resolvedDir = resolvePlaceholders(in: configDir)
            copyBundledGoogleCredentials(to: resolvedDir)
        }

        // Resolve placeholders in args and env
        let resolvedArgs = config.args.map { resolvePlaceholders(in: $0) }
        let resolvedEnv = config.env?.mapValues { resolvePlaceholders(in: $0) }

        // Build the full shell command string
        var shellParts: [String] = []

        // Prepend env vars
        if let env = resolvedEnv {
            for (key, value) in env {
                shellParts.append("export \(key)='\(value)'")
            }
        }

        // Build command with args
        let cmdString = ([config.command] + resolvedArgs)
            .map { $0.contains(" ") ? "'\($0)'" : $0 }
            .joined(separator: " ")
        shellParts.append(cmdString)

        let fullCommand = shellParts.joined(separator: " && ")

        // If the command needs browser access, run it and auto-open the OAuth URL
        if config.openInTerminal == true {
            let result = await runCommandAndOpenURL(fullCommand)
            if result.success {
                commandState = .success
                commandOutput = config.successMessage
            } else {
                commandState = .error(message: result.output.isEmpty ? "Authentication failed" : String(result.output.prefix(200)))
            }
            return
        }

        let result = await runShellCommand(fullCommand)

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

    // MARK: - Terminal

    /// Run a command that outputs an OAuth URL, capture it, open in browser, and wait for completion.
    private func runCommandAndOpenURL(_ command: String) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let urlOpenedBox = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
                urlOpenedBox.initialize(to: false)
                let lock = NSLock()

                // Watch stdout for the OAuth URL and open it immediately
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let chunk = String(data: data, encoding: .utf8) ?? ""

                    lock.lock()
                    let alreadyOpened = urlOpenedBox.pointee
                    lock.unlock()

                    if !alreadyOpened {
                        for line in chunk.components(separatedBy: .newlines) {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("https://accounts.google.com") {
                                lock.lock()
                                urlOpenedBox.pointee = true
                                lock.unlock()
                                if let url = URL(string: trimmed) {
                                    DispatchQueue.main.async {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                break
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    stdoutPipe.fileHandleForReading.readabilityHandler = nil

                    lock.lock()
                    let opened = urlOpenedBox.pointee
                    lock.unlock()
                    urlOpenedBox.deallocate()

                    continuation.resume(returning: ProcessResult(
                        success: process.terminationStatus == 0,
                        output: opened ? "Authentication complete" : "No OAuth URL found"
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

    // MARK: - Google Credentials

    /// Copy bundled OAuth client_secret.json to the per-account config directory
    /// so `gws auth login` can use it without requiring `gws auth setup`.
    private func copyBundledGoogleCredentials(to configDir: String) {
        let fm = FileManager.default
        let destDir = URL(fileURLWithPath: configDir)
        let destFile = destDir.appendingPathComponent("client_secret.json")

        // Skip if already exists (e.g., re-running wizard)
        guard !fm.fileExists(atPath: destFile.path) else { return }

        guard let bundledURL = Bundle.main.url(forResource: "gws-client-secret", withExtension: "json") else {
            print("[SetupWizard] gws-client-secret.json not found in app bundle")
            return
        }

        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            try fm.copyItem(at: bundledURL, to: destFile)

            // Set restrictive permissions (600)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destFile.path)
        } catch {
            print("[SetupWizard] Failed to copy Google credentials: \(error)")
        }
    }

    // MARK: - Process Execution

    private struct ProcessResult {
        let success: Bool
        let output: String
    }

    /// Run a command string through a login shell to inherit PATH (nvm, Homebrew, etc.)
    private func runShellCommand(_ command: String) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                // Disable interactive TUI features
                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = env

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    var output = String(data: data, encoding: .utf8) ?? ""

                    // Strip ANSI escape codes
                    output = Self.stripAnsiCodes(output)

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

    private static func stripAnsiCodes(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[a-zA-Z]|\\x1B\\[\\?[0-9]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
