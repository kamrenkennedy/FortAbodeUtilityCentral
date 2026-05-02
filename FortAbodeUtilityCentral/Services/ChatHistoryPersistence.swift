import Foundation

// Atomic JSON persistence for the Claude Chat thread.
//
// File: `~/Library/Application Support/FortAbodeUtilityCentral/chat-history.json`
// Schema-versioned (`schemaVersion: 1`). Atomic writes (`Data.write(options:
// [.atomic])`) so a crash mid-write can't corrupt the live file.
//
// Rollover: when the live file exceeds `maxLiveMessages` (500), the oldest
// half spills into a sibling `chat-history-archive-{ISODate}.json`. We keep
// the second half hot so the user still has recent context. Archives are
// never read back — they're a paper trail.
//
// Cross-Mac: deliberately PER-MACHINE. Family Chat (Y5) is the cross-Mac
// surface; Claude Chat is local. Don't move this to iCloud without a
// conflict-resolution strategy.

public actor ChatHistoryPersistence {

    public static let maxLiveMessages: Int = 500

    private let directory: URL
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.directory = dir
        self.fileURL = dir.appendingPathComponent("chat-history.json")
    }

    public static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("FortAbodeUtilityCentral")
    }

    /// Read the live file. Returns an empty file (no messages) if the file
    /// doesn't exist or fails to decode — startup never blocks on a corrupt
    /// history.
    public func load() async -> ChatHistoryFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ChatHistoryFile(sessionID: "", messages: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(ChatHistoryFile.self, from: data)
            return file
        } catch {
            await ErrorLogger.shared.log(
                area: "ClaudeChat.History.loadFailed",
                message: "Could not decode chat-history.json — starting fresh",
                context: ["error": "\(error)", "path": fileURL.path]
            )
            return ChatHistoryFile(sessionID: "", messages: [])
        }
    }

    /// Save the file atomically. If `messages.count` exceeds `maxLiveMessages`,
    /// the oldest half is archived to a dated sibling file before the live
    /// file is rewritten.
    public func save(_ file: ChatHistoryFile) async throws {
        try ensureDirectoryExists()

        var rolled = file
        if rolled.messages.count > Self.maxLiveMessages {
            let half = rolled.messages.count / 2
            let archiveSlice = Array(rolled.messages.prefix(half))
            try await archive(messages: archiveSlice, sessionID: rolled.sessionID)
            rolled.messages = Array(rolled.messages.suffix(from: half))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rolled)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Wipe the live file. Archives are untouched. Used by `clearConversation`
    /// in the store.
    public func clear() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            await ErrorLogger.shared.log(
                area: "ClaudeChat.History.clearFailed",
                message: "Could not delete chat-history.json",
                context: ["error": "\(error)"]
            )
        }
    }

    /// File path the live history is written to. Exposed for diagnostic
    /// surfacing (e.g. surfacing the path in Settings).
    public func liveFilePath() -> String {
        fileURL.path
    }

    // MARK: - Private

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func archive(messages: [ChatTurn], sessionID: String) async throws {
        let stamp = Self.iso8601.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveURL = directory.appendingPathComponent("chat-history-archive-\(stamp).json")
        let archive = ChatHistoryFile(
            schemaVersion: 1,
            sessionID: sessionID,
            lastUpdated: Date(),
            messages: messages
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: archiveURL, options: [.atomic])
    }

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
