import Foundation

// MARK: - Component Type

enum ComponentType: String, Codable, CaseIterable {
    case npmPackage
    case mcpServer
    case localMCPServer
    case skill

    var label: String {
        switch self {
        case .npmPackage: return "npm Package"
        case .mcpServer: return "MCP Server"
        case .localMCPServer: return "Local MCP Server"
        case .skill: return "Skill"
        }
    }
}

// MARK: - Included Server (MCP servers provided by a package)

struct IncludedServer: Codable, Hashable {
    let name: String
    let description: String
}

// MARK: - Version Source (how to find installed version)

enum VersionSource: Hashable {
    case npxCache(packageName: String)
    case localDirectory(name: String)
    case packageJSON(path: String)
    case claudeDesktopConfig(serverKey: String)
    case icloudTemplateVersion(relativePath: String)
}

extension VersionSource: Codable {
    private struct NpxCachePayload: Codable { let packageName: String }
    private struct LocalDirectoryPayload: Codable { let name: String }
    private struct PackageJSONPayload: Codable { let path: String }
    private struct ClaudeDesktopPayload: Codable { let serverKey: String }
    private struct ICloudTemplatePayload: Codable { let relativePath: String }

    private enum CodingKeys: String, CodingKey {
        case npxCache, localDirectory, packageJson, claudeDesktopConfig, icloudTemplateVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try container.decodeIfPresent(NpxCachePayload.self, forKey: .npxCache) {
            self = .npxCache(packageName: payload.packageName)
        } else if let payload = try container.decodeIfPresent(LocalDirectoryPayload.self, forKey: .localDirectory) {
            self = .localDirectory(name: payload.name)
        } else if let payload = try container.decodeIfPresent(PackageJSONPayload.self, forKey: .packageJson) {
            self = .packageJSON(path: payload.path)
        } else if let payload = try container.decodeIfPresent(ClaudeDesktopPayload.self, forKey: .claudeDesktopConfig) {
            self = .claudeDesktopConfig(serverKey: payload.serverKey)
        } else if let payload = try container.decodeIfPresent(ICloudTemplatePayload.self, forKey: .icloudTemplateVersion) {
            self = .icloudTemplateVersion(relativePath: payload.relativePath)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown VersionSource type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .npxCache(let packageName):
            try container.encode(NpxCachePayload(packageName: packageName), forKey: .npxCache)
        case .localDirectory(let name):
            try container.encode(LocalDirectoryPayload(name: name), forKey: .localDirectory)
        case .packageJSON(let path):
            try container.encode(PackageJSONPayload(path: path), forKey: .packageJson)
        case .claudeDesktopConfig(let serverKey):
            try container.encode(ClaudeDesktopPayload(serverKey: serverKey), forKey: .claudeDesktopConfig)
        case .icloudTemplateVersion(let relativePath):
            try container.encode(ICloudTemplatePayload(relativePath: relativePath), forKey: .icloudTemplateVersion)
        }
    }
}

// MARK: - Update Source (where to check for latest version)

enum UpdateSource: Hashable {
    case githubRelease(owner: String, repo: String)
    case npmRegistry(packageName: String)
    case none
}

extension UpdateSource: Codable {
    private struct GitHubPayload: Codable { let owner: String; let repo: String }
    private struct NpmPayload: Codable { let packageName: String }

    private enum CodingKeys: String, CodingKey {
        case githubRelease, npmRegistry
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let str = try? singleValue.decode(String.self),
           str == "none" {
            self = .none
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try container.decodeIfPresent(GitHubPayload.self, forKey: .githubRelease) {
            self = .githubRelease(owner: payload.owner, repo: payload.repo)
        } else if let payload = try container.decodeIfPresent(NpmPayload.self, forKey: .npmRegistry) {
            self = .npmRegistry(packageName: payload.packageName)
        } else {
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .githubRelease(let owner, let repo):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(GitHubPayload(owner: owner, repo: repo), forKey: .githubRelease)
        case .npmRegistry(let packageName):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(NpmPayload(packageName: packageName), forKey: .npmRegistry)
        case .none:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        }
    }
}

// MARK: - Update Command (how to perform the update)

enum UpdateCommand: Hashable {
    case npxInstall(packageName: String)
    case shellCommand(command: String, args: [String])
    case none
}

extension UpdateCommand: Codable {
    private struct NpxPayload: Codable { let packageName: String }
    private struct ShellPayload: Codable { let command: String; let args: [String] }

    private enum CodingKeys: String, CodingKey {
        case npxInstall, shellCommand
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let str = try? singleValue.decode(String.self),
           str == "none" {
            self = .none
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try container.decodeIfPresent(NpxPayload.self, forKey: .npxInstall) {
            self = .npxInstall(packageName: payload.packageName)
        } else if let payload = try container.decodeIfPresent(ShellPayload.self, forKey: .shellCommand) {
            self = .shellCommand(command: payload.command, args: payload.args)
        } else {
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .npxInstall(let packageName):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(NpxPayload(packageName: packageName), forKey: .npxInstall)
        case .shellCommand(let command, let args):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ShellPayload(command: command, args: args), forKey: .shellCommand)
        case .none:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        }
    }
}

// MARK: - Setup Flow (declarative wizard for configurable components)

struct SetupFlow: Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let steps: [SetupStep]
}

struct SetupStep: Codable, Hashable, Identifiable {
    let id: String
    let type: SetupStepType
    let title: String
    let subtitle: String?
    let body: String
    let illustration: StepIllustration?
    let actionLabel: String
    let externalUrl: String?
    let inputConfig: InputConfig?
    let runConfig: RunConfig?
    let summaryFields: [String]?
}

struct RunConfig: Codable, Hashable {
    let command: String
    let args: [String]
    let env: [String: String]?
    let successMessage: String
    let globalInstall: String?
    let openInTerminal: Bool?
}

enum SetupStepType: String, Codable, Hashable {
    case instruction
    case textInput = "text_input"
    case secureInput = "secure_input"
    case multiChoice = "multi_choice"
    case runCommand = "run_command"
    case completion
}

struct StepIllustration: Codable, Hashable {
    let type: IllustrationType
    let name: String

    enum IllustrationType: String, Codable, Hashable {
        case sfSymbol = "sf_symbol"
        case bundledImage = "bundled_image"
    }
}

struct InputConfig: Codable, Hashable {
    let fieldName: String
    let placeholder: String?
    let validation: InputValidation?
    let validateAction: ValidateAction?
    let options: [ChoiceOption]?
}

struct InputValidation: Codable, Hashable {
    let type: ValidationType
    let pattern: String?
    let minLength: Int?
    let errorMessage: String

    enum ValidationType: String, Codable, Hashable {
        case regex
        case notEmpty = "not_empty"
        case minLength = "min_length"
    }
}

struct ValidateAction: Codable, Hashable {
    let type: ValidateActionType
    let endpoint: String?

    enum ValidateActionType: String, Codable, Hashable {
        case notionToken = "notion_token"
        case httpGet = "http_get"
        case custom
    }
}

struct ChoiceOption: Codable, Hashable {
    let value: String
    let label: String
    let description: String?
}

// MARK: - Claude Desktop Config Entry

struct ClaudeConfigEntry: Codable, Hashable {
    let key: String
    let command: String
    let args: [String]
    let env: [String: String]?
}

// MARK: - Component

struct Component: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let description: String
    let userDescription: String?
    let usageInstructions: String?
    let type: ComponentType
    let icon: String?
    let includedServers: [IncludedServer]?
    let claudeConfig: [ClaudeConfigEntry]?
    let versionSource: VersionSource
    let updateSource: UpdateSource
    let updateCommand: UpdateCommand
    let marketplace: Bool?
    let setupFlow: SetupFlow?
    let multiInstance: Bool?
    let minAppVersion: String?

    /// SF Symbol name — uses the explicit icon if provided, otherwise falls back by type
    var iconName: String {
        if let icon { return icon }
        switch type {
        case .npmPackage: return "shippingbox.fill"
        case .mcpServer: return "server.rack"
        case .localMCPServer: return "desktopcomputer"
        case .skill: return "sparkles"
        }
    }

    /// Whether this component can be updated
    var isUpdatable: Bool {
        if case .none = updateCommand { return false }
        return true
    }

    /// Whether this component should appear in the marketplace when not installed
    var showInMarketplace: Bool {
        marketplace ?? false
    }

    /// Whether this component requires a setup wizard before install
    var requiresSetup: Bool {
        setupFlow != nil
    }

    /// Whether this component is compatible with the running app version
    var isCompatibleWithCurrentApp: Bool {
        guard let required = minAppVersion else { return true }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return current.compare(required, options: .numeric) != .orderedAscending
    }
}
