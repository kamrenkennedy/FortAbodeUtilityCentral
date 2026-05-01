import Foundation
import Observation

// MARK: - Claude Chat Store
//
// `@Observable` UI-facing state for Y6 Claude Chat. Owns the message thread,
// the per-turn runner, persistence, CLI detection, and the Tools toggle.
// Pattern matches `WeeklyRhythmEngineStore` — sync init, async `loadHistory`
// called from a `.task` modifier, no optional-sentinel in app wiring.
//
// Concurrency: streamed events arrive on the parser's background queue; each
// `onEvent` callback dispatches a `Task { @MainActor }` to apply the mutation
// on the store. MainActor's FIFO semantics keep the deltas in order.

@MainActor
@Observable
public final class ClaudeChatStore {

    public private(set) var messages: [ChatTurn] = []
    public var toolsEnabled: Bool {
        didSet { UserDefaults.standard.set(toolsEnabled, forKey: Self.toolsEnabledKey) }
    }
    public private(set) var isStreaming: Bool = false
    public private(set) var lastError: String?
    public private(set) var cliDetection: ClaudeCLIDetector.Result = .notFound

    private let runner: ClaudeChatTurnRunner
    private let persistence: ChatHistoryPersistence
    private let detector: ClaudeCLIDetector
    private var sessionID: UUID

    private static let toolsEnabledKey = "claudeChat.toolsEnabled"
    private static let sessionIDKey = "claudeChat.sessionID"
    private static let sessionEstablishedKey = "claudeChat.sessionEstablished"

    private static let inputBreadcrumbCharLimit = 200
    private static let outputBreadcrumbCharLimit = 500

    public init(
        runner: ClaudeChatTurnRunner = ClaudeChatTurnRunner(),
        persistence: ChatHistoryPersistence = ChatHistoryPersistence(),
        detector: ClaudeCLIDetector = ClaudeCLIDetector()
    ) {
        self.runner = runner
        self.persistence = persistence
        self.detector = detector
        self.toolsEnabled = UserDefaults.standard.bool(forKey: Self.toolsEnabledKey)
        self.sessionID = Self.loadOrGenerateSessionID()
    }

    /// Hydrate `messages` from disk and warm CLI detection. Call from a
    /// `.task` modifier on first appearance — never from `init` so SwiftUI
    /// gets a synchronous environment value.
    public func loadHistory() async {
        let file = await persistence.load()

        // Heal any turn that was streaming when the app quit. Without this,
        // a re-launched assistant bubble would render the streaming caret
        // forever and look like the engine is stuck.
        var healed = file.messages
        for i in healed.indices where healed[i].isStreaming {
            healed[i].isStreaming = false
            if healed[i].content.isEmpty && healed[i].failureReason == nil {
                healed[i].failureReason = "Turn was interrupted (app quit while streaming)."
            }
        }
        self.messages = healed

        // Migration: builds before Phase 5a passed --session-id on every spawn
        // (which the CLI rejects on the second use with "Session ID is already
        // in use"). On the upgrade path, the server-side session is already
        // established — flag it so the first turn of the new build uses
        // --resume instead of trying to create the same session again.
        if UserDefaults.standard.object(forKey: Self.sessionEstablishedKey) == nil,
           !healed.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.sessionEstablishedKey)
        }

        // Detect CLI in the background; first send will re-detect if this is
        // still .notFound by then.
        Task { [detector] in
            let result = await detector.detect()
            await MainActor.run { self.cliDetection = result }
        }
    }

    /// Send one user message and stream the assistant reply. Drops calls
    /// while another turn is in flight (UI guards send button via
    /// `isStreaming`, but defend in depth).
    public func sendUserMessage(_ text: String) async {
        guard !isStreaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Lazy re-detect if first detection hadn't landed yet (or returned .notFound).
        if case .notFound = cliDetection {
            cliDetection = await detector.detect()
        }

        guard case .found(let cliPath, _) = cliDetection else {
            let userMsg = ChatTurn(role: .user, content: trimmed)
            let failed = ChatTurn(
                role: .assistant,
                failureReason: "Claude CLI not found. Install it from claude.ai/code or pin a custom path in Settings."
            )
            messages.append(userMsg)
            messages.append(failed)
            await persist()
            return
        }

        let userMessage = ChatTurn(role: .user, content: trimmed)
        let placeholder = ChatTurn(role: .assistant, isStreaming: true)
        messages.append(userMessage)
        messages.append(placeholder)
        isStreaming = true
        lastError = nil

        let placeholderID = placeholder.id
        let tools = toolsEnabled
        let session = sessionID
        let mode: ClaudeChatTurnRunner.SessionMode =
            UserDefaults.standard.bool(forKey: Self.sessionEstablishedKey) ? .resuming : .creating

        await runner.run(
            cliPath: cliPath,
            sessionID: session,
            sessionMode: mode,
            userMessage: trimmed,
            toolsEnabled: tools
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyEvent(event, toMessageID: placeholderID)
            }
        }

        isStreaming = false
        await persist()
    }

    /// Wipe the on-disk history AND in-memory thread, and rotate the session
    /// ID so the next turn starts a fresh server-side context.
    public func clearConversation() async {
        messages.removeAll()
        await persistence.clear()
        sessionID = UUID()
        UserDefaults.standard.set(sessionID.uuidString, forKey: Self.sessionIDKey)
        UserDefaults.standard.set(false, forKey: Self.sessionEstablishedKey)
    }

    /// Diagnostic accessor — current chat-history.json path. Useful for the
    /// Settings pane "Reveal in Finder" affordance.
    public func liveHistoryPath() async -> String {
        await persistence.liveFilePath()
    }

    // MARK: - Event application

    private func applyEvent(_ event: ClaudeChatEvent, toMessageID id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .partialAssistantText(let delta):
            messages[idx].content += delta

        case .toolUseCompleted(let name, let input, let succeeded, let output):
            messages[idx].toolBreadcrumbs.append(ToolBreadcrumb(
                toolName: name,
                inputSummary: String(input.prefix(Self.inputBreadcrumbCharLimit)),
                succeeded: succeeded,
                output: output.map { String($0.prefix(Self.outputBreadcrumbCharLimit)) }
            ))

        case .turnComplete:
            messages[idx].isStreaming = false
            // Server-side session is now established. Subsequent turns must
            // use --resume <UUID> instead of --session-id <UUID>, otherwise
            // the CLI rejects them with "Session ID is already in use".
            UserDefaults.standard.set(true, forKey: Self.sessionEstablishedKey)

        case .turnFailed(let reason):
            messages[idx].isStreaming = false
            messages[idx].failureReason = reason

        case .terminated(let exitCode):
            messages[idx].isStreaming = false
            // If we got nothing useful and the process exited non-zero,
            // surface a fallback failure message so the bubble isn't blank.
            if messages[idx].content.isEmpty,
               messages[idx].toolBreadcrumbs.isEmpty,
               messages[idx].failureReason == nil,
               exitCode != 0 {
                messages[idx].failureReason = "Claude CLI exited with code \(exitCode)."
            }
        }
    }

    private func persist() async {
        let file = ChatHistoryFile(
            schemaVersion: 1,
            sessionID: sessionID.uuidString,
            lastUpdated: Date(),
            messages: messages
        )
        do {
            try await persistence.save(file)
        } catch {
            lastError = "Could not save chat history: \(error.localizedDescription)"
        }
    }

    private static func loadOrGenerateSessionID() -> UUID {
        if let raw = UserDefaults.standard.string(forKey: sessionIDKey),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        let new = UUID()
        UserDefaults.standard.set(new.uuidString, forKey: sessionIDKey)
        return new
    }
}
