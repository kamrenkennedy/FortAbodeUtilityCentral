import Foundation

// One row in the Claude Chat thread. Either a user prompt or an assistant
// reply (system messages are reserved for future "context inserted" notices).
// Tool breadcrumbs render as small chips below the assistant bubble for the
// turn that produced them. Named `ChatTurn` rather than `ChatMessage` to avoid
// filename ambiguity with `Views/Chat/ChatMessage.swift` (which holds
// `MessageBubble`/`AttachmentChip`/`RichCardMessage` view code).

public struct ChatTurn: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let role: Role
    public var timestamp: Date
    /// Streamed assistant text accumulates here as `text_delta` events arrive.
    /// For user turns, this is set once at send time and never mutated.
    public var content: String
    /// True while `ClaudeChatTurnRunner` is still emitting events for this
    /// turn. The view appends a caret while this is true.
    public var isStreaming: Bool
    public var toolBreadcrumbs: [ToolBreadcrumb]
    /// Populated on `.turnFailed` / non-zero exit. Renders as a warning bubble
    /// instead of regular content.
    public var failureReason: String?

    public enum Role: String, Codable, Sendable, Hashable {
        case user, assistant, system
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        timestamp: Date = Date(),
        content: String = "",
        isStreaming: Bool = false,
        toolBreadcrumbs: [ToolBreadcrumb] = [],
        failureReason: String? = nil
    ) {
        self.id = id
        self.role = role
        self.timestamp = timestamp
        self.content = content
        self.isStreaming = isStreaming
        self.toolBreadcrumbs = toolBreadcrumbs
        self.failureReason = failureReason
    }
}

/// Post-hoc record of a tool the assistant used during this turn. Input and
/// output are pre-truncated by the store so the breadcrumb stays compact in
/// the UI and small on disk (chat-history.json grows slowly).
public struct ToolBreadcrumb: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let toolName: String
    /// Truncated JSON-string representation of the tool's `input` argument
    /// (≤200 chars from the store).
    public let inputSummary: String
    public let succeeded: Bool
    /// Truncated tool output (≤500 chars from the store). Nil for tools that
    /// returned no content or were blocked.
    public let output: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        toolName: String,
        inputSummary: String,
        succeeded: Bool,
        output: String?,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.inputSummary = inputSummary
        self.succeeded = succeeded
        self.output = output
        self.timestamp = timestamp
    }
}

/// On-disk schema for `chat-history.json`. Versioned so future schema changes
/// can migrate cleanly. The store re-writes the entire file atomically after
/// each turn settles.
public struct ChatHistoryFile: Codable, Sendable {
    public let schemaVersion: Int
    public let sessionID: String
    public let lastUpdated: Date
    public var messages: [ChatTurn]

    public init(schemaVersion: Int = 1, sessionID: String, lastUpdated: Date = Date(), messages: [ChatTurn]) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.lastUpdated = lastUpdated
        self.messages = messages
    }
}
