import Foundation

/// File-backed messaging between Kam and Tiera. Reads .md files from each
/// user's `Weekly Rhythm/{user}/messages/inbox/` directory and writes new
/// ones into the partner's inbox to send. Conversation is reconstructed
/// by merging both inboxes — both Macs see both folders via iCloud Folder
/// Sharing, so the chat pane shows a complete history regardless of which
/// machine each message originated from.
///
/// Path resolution reuses `WeeklyRhythmPathResolver` so the legacy
/// `Weekly Flow/` root is supported as a fallback during the rename
/// transition.
///
/// All writes are atomic via `Data.write(options: .atomic)` — partial files
/// would otherwise be visible to the other Mac mid-iCloud-sync.
actor FamilyMessagesService {

    private let fm = FileManager.default
    private let resolver = WeeklyRhythmPathResolver()

    enum MessagesError: LocalizedError {
        case folderUnavailable
        case invalidDraft(String)
        case writeFailed(String)
        case partnerUnknown
        case attachmentCopyFailed(URL, String)

        var errorDescription: String? {
            switch self {
            case .folderUnavailable:    return "Weekly Rhythm folder not available."
            case .invalidDraft(let m):  return "Invalid message draft: \(m)"
            case .writeFailed(let m):   return "Failed to send message: \(m)"
            case .partnerUnknown:       return "Couldn't determine partner — only one user folder exists."
            case .attachmentCopyFailed(let url, let m):
                return "Failed to attach \(url.lastPathComponent): \(m)"
            }
        }
    }

    // MARK: - Identity

    /// Active user — same fallback chain `FamilyHealthDashboard` uses.
    nonisolated static func activeUserName() -> String {
        if let stored = UserDefaults.standard.string(forKey: AppSettingsKey.weeklyRhythmActiveUserName),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        let full = NSFullUserName()
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Partner = the other user folder under Weekly Rhythm/. For the Kennedy
    /// family case there are exactly two: Kamren and Tiera. Returns nil if
    /// only one user folder exists (no partner to send to).
    func partnerUserName(activeUser: String) -> String? {
        guard let resolved = resolver.resolve() else { return nil }
        let entries = (try? fm.contentsOfDirectory(atPath: resolved.rootPath)) ?? []
        let candidates = entries.filter { entry in
            var isDir: ObjCBool = false
            let entryPath = "\(resolved.rootPath)/\(entry)"
            return fm.fileExists(atPath: entryPath, isDirectory: &isDir)
                && isDir.boolValue
                && fm.fileExists(atPath: "\(entryPath)/messages")
                && entry != activeUser
        }
        return candidates.first
    }

    // MARK: - Read

    /// Load the full conversation between the active user and the partner.
    /// Reads BOTH inboxes (active user's inbox = messages partner sent to me,
    /// partner's inbox = messages I sent to them) and merges by timestamp.
    func loadConversation() async -> [FamilyMessage] {
        let active = Self.activeUserName()
        guard let resolved = resolver.resolve() else { return [] }
        guard let partner = partnerUserName(activeUser: active) else {
            // Single-user case — show the active user's inbox only (anything
            // an outside party may have dropped in there).
            return await loadInbox(at: inboxPath(root: resolved.rootPath, user: active), recipient: active)
        }
        let activeInbox = await loadInbox(
            at: inboxPath(root: resolved.rootPath, user: active),
            recipient: active
        )
        let partnerInbox = await loadInbox(
            at: inboxPath(root: resolved.rootPath, user: partner),
            recipient: partner
        )
        return (activeInbox + partnerInbox).sorted { $0.timestamp < $1.timestamp }
    }

    private func loadInbox(at path: String, recipient: String) async -> [FamilyMessage] {
        guard fm.fileExists(atPath: path),
              let entries = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }
        var messages: [FamilyMessage] = []
        for entry in entries {
            guard entry.hasSuffix(".md") else { continue }
            let full = "\(path)/\(entry)"
            if let parsed = parseMessageFile(at: full, recipient: recipient) {
                messages.append(parsed)
            }
        }
        return messages
    }

    // MARK: - Write

    /// Mark a message as read. Atomic in-place rewrite of the same file —
    /// only the frontmatter `status` and `read_at` lines change.
    func markAsRead(_ message: FamilyMessage) async {
        guard message.status == .unread else { return }
        guard let raw = try? String(contentsOfFile: message.absolutePath, encoding: .utf8) else { return }

        let now = Date()
        let isoNow = Self.iso8601.string(from: now)

        var (front, body) = splitFrontmatter(raw)
        front = upsertField(front, key: "status", value: "read")
        front = upsertField(front, key: "read_at", value: isoNow)
        let combined = "---\n\(front)---\n\(body)"

        let url = URL(fileURLWithPath: message.absolutePath)
        do {
            try combined.data(using: .utf8)?.write(to: url, options: [.atomic])
        } catch {
            await ErrorLogger.shared.log(
                area: "FamilyMessagesService.markAsRead",
                message: "Failed to mark \(message.filename) as read: \(error.localizedDescription)"
            )
        }
    }

    /// Send a new message to the partner. Writes a `.md` file into the
    /// partner's inbox and returns the populated `FamilyMessage` so the
    /// caller can append it to its UI state immediately (without waiting
    /// for an inbox reload).
    @discardableResult
    func send(draft: FamilyMessageDraft) async throws -> FamilyMessage {
        let active = Self.activeUserName()
        guard let resolved = resolver.resolve() else {
            throw MessagesError.folderUnavailable
        }
        guard let partner = partnerUserName(activeUser: active) else {
            throw MessagesError.partnerUnknown
        }

        let trimmedSubject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty || !trimmedBody.isEmpty else {
            throw MessagesError.invalidDraft("subject and body both empty")
        }

        let now = Date()
        let inbox = inboxPath(root: resolved.rootPath, user: partner)
        try? fm.createDirectory(atPath: inbox, withIntermediateDirectories: true)

        let filename = makeFilename(timestamp: now, sender: active, category: draft.category)
        let path = "\(inbox)/\(filename)"
        let stem = filename.replacingOccurrences(of: ".md", with: "")

        // Copy attachments BEFORE writing the .md so a half-sent message
        // (md present, attachments missing) is impossible. If any copy fails,
        // delete the partial subdirectory and abort.
        let attachmentsDir = attachmentsDirectoryPath(
            root: resolved.rootPath,
            user: partner,
            messageStem: stem
        )
        var copiedAttachmentURLs: [URL] = []
        var attachmentRelativePaths: [String] = []
        if !draft.attachments.isEmpty {
            do {
                try fm.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)
            } catch {
                throw MessagesError.attachmentCopyFailed(
                    URL(fileURLWithPath: attachmentsDir),
                    "mkdir: \(error.localizedDescription)"
                )
            }
            for source in draft.attachments {
                let destName = source.lastPathComponent
                let destPath = "\(attachmentsDir)/\(destName)"
                let destURL = URL(fileURLWithPath: destPath)
                do {
                    if fm.fileExists(atPath: destPath) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: source, to: destURL)
                    copiedAttachmentURLs.append(destURL)
                    attachmentRelativePaths.append("../attachments/\(stem)/\(destName)")
                } catch {
                    // Roll back partial copies.
                    try? fm.removeItem(atPath: attachmentsDir)
                    throw MessagesError.attachmentCopyFailed(source, error.localizedDescription)
                }
            }
        }

        let frontmatter = renderFrontmatter(
            from: active,
            category: draft.category,
            urgency: draft.urgency,
            subject: trimmedSubject.isEmpty ? "(no subject)" : trimmedSubject,
            status: .unread,
            readAt: nil,
            actionItems: draft.actionItems,
            attachments: attachmentRelativePaths
        )
        let bodyBlock = trimmedBody.isEmpty ? "" : "\n" + trimmedBody + "\n"
        let combined = "---\n\(frontmatter)---\n\(bodyBlock)"

        let url = URL(fileURLWithPath: path)
        do {
            try combined.data(using: .utf8)?.write(to: url, options: [.atomic])
        } catch {
            // Clean up any attachments we copied — without the .md they're
            // orphaned and would never be referenced.
            if !attachmentRelativePaths.isEmpty {
                try? fm.removeItem(atPath: attachmentsDir)
            }
            throw MessagesError.writeFailed(error.localizedDescription)
        }

        return FamilyMessage(
            id: stem,
            filename: filename,
            absolutePath: path,
            from: active,
            recipient: partner,
            category: draft.category,
            urgency: draft.urgency,
            subject: trimmedSubject.isEmpty ? "(no subject)" : trimmedSubject,
            status: .unread,
            readAt: nil,
            actionItems: draft.actionItems,
            body: trimmedBody,
            timestamp: now,
            attachments: copiedAttachmentURLs
        )
    }

    // MARK: - Path helpers

    private func inboxPath(root: String, user: String) -> String {
        "\(root)/\(user)/messages/inbox"
    }

    /// Per-message attachments subdirectory. The stem matches the message's
    /// filename without the .md extension, so the attachments folder sits
    /// adjacent to its message in a Finder-sorted listing.
    private func attachmentsDirectoryPath(root: String, user: String, messageStem: String) -> String {
        "\(root)/\(user)/messages/attachments/\(messageStem)"
    }

    private func makeFilename(timestamp: Date, sender: String, category: String) -> String {
        let iso = Self.iso8601.string(from: timestamp)
        // `:` is unsafe in filenames on case-insensitive HFS+; substitute the
        // time-portion colons with dashes. Keep T separator and Z suffix.
        let safe = iso.replacingOccurrences(of: ":", with: "-")
        let safeCategory = category
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(safe)-\(sender)-\(safeCategory).md"
    }

    // MARK: - Frontmatter parsing
    //
    // Hand-rolled YAML-lite because we only need a dozen scalar fields plus a
    // simple string-array (`action_items:`). Pulling in a YAML dependency for
    // this surface would be overkill, and the engine writes the same shape
    // by hand on its end.

    private func parseMessageFile(at path: String, recipient: String) -> FamilyMessage? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let (frontmatter, body) = splitFrontmatter(raw)
        let fields = parseScalarFields(frontmatter)
        let actionItems = parseListField(frontmatter, key: "action_items")
        let attachmentRelPaths = parseListField(frontmatter, key: "attachments")

        let filename = (path as NSString).lastPathComponent
        let id = filename.replacingOccurrences(of: ".md", with: "")
        let timestamp = parseTimestampFromFilename(filename) ?? Date()

        let from = fields["from"] ?? "Unknown"
        let category = fields["category"] ?? "other"
        let urgency = FamilyMessage.Urgency(rawValue: fields["urgency"] ?? "normal") ?? .normal
        let subject = fields["subject"] ?? "(no subject)"
        let status = FamilyMessage.ReadStatus(rawValue: fields["status"] ?? "unread") ?? .unread
        let readAt = fields["read_at"].flatMap { Self.iso8601.date(from: $0) }

        // Resolve relative attachment paths against the message's inbox dir.
        // Frontmatter stores `../attachments/<stem>/<filename>` so it's
        // portable across machines; here we hydrate to absolute URLs the
        // view can hand directly to NSWorkspace.
        let inboxDir = (path as NSString).deletingLastPathComponent
        let attachments: [URL] = attachmentRelPaths.compactMap { rel in
            let combined = (inboxDir as NSString).appendingPathComponent(rel)
            let normalized = (combined as NSString).standardizingPath
            return fm.fileExists(atPath: normalized) ? URL(fileURLWithPath: normalized) : nil
        }

        return FamilyMessage(
            id: id,
            filename: filename,
            absolutePath: path,
            from: from,
            recipient: recipient,
            category: category,
            urgency: urgency,
            subject: subject,
            status: status,
            readAt: readAt,
            actionItems: actionItems,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: timestamp,
            attachments: attachments
        )
    }

    private func splitFrontmatter(_ raw: String) -> (frontmatter: String, body: String) {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ("", raw)
        }
        var frontmatterLines: [String] = []
        var bodyLines: [String] = []
        var inFrontmatter = true
        for (i, line) in lines.enumerated() where i > 0 {
            if inFrontmatter && line.trimmingCharacters(in: .whitespaces) == "---" {
                inFrontmatter = false
                continue
            }
            if inFrontmatter {
                frontmatterLines.append(line)
            } else {
                bodyLines.append(line)
            }
        }
        return (frontmatterLines.joined(separator: "\n") + "\n", bodyLines.joined(separator: "\n"))
    }

    /// Scalar fields are `key: value` per line. List fields (`action_items:`,
    /// `attachments:`) are skipped here and handled by `parseListField`.
    private static let listKeys: Set<String> = ["action_items", "attachments"]

    private func parseScalarFields(_ frontmatter: String) -> [String: String] {
        var out: [String: String] = [:]
        var skipUntilDedent = false
        for rawLine in frontmatter.components(separatedBy: "\n") {
            let line = rawLine
            if line.hasPrefix(" ") || line.hasPrefix("-") || line.hasPrefix("\t") {
                if skipUntilDedent { continue }
            } else {
                skipUntilDedent = false
            }
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                // Either nil scalar OR start of a list. Mark for skip if it's
                // a known list key; either way the scalar map gets nil.
                if Self.listKeys.contains(key) {
                    skipUntilDedent = true
                }
                continue
            }
            // Strip optional surrounding quotes for cleaner display.
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            out[key] = unquoted
        }
        return out
    }

    /// Look for a `key:` line followed by `  - "..."` indented entries.
    private func parseListField(_ frontmatter: String, key: String) -> [String] {
        var out: [String] = []
        var capturing = false
        for rawLine in frontmatter.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if !capturing {
                if trimmed.hasPrefix("\(key):") {
                    let inline = trimmed.dropFirst("\(key):".count).trimmingCharacters(in: .whitespaces)
                    if inline.isEmpty {
                        capturing = true
                    }
                }
                continue
            }
            // Capturing: indented `-` lines belong to the list; anything else ends it.
            if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
                if let dashIdx = trimmed.firstIndex(of: "-") {
                    let item = String(trimmed[trimmed.index(after: dashIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !item.isEmpty {
                        out.append(item)
                    }
                }
            } else {
                capturing = false
            }
        }
        return out
    }

    private func parseTimestampFromFilename(_ filename: String) -> Date? {
        // Filename starts with `2026-04-30T20-15-00Z`. Re-add the colons
        // before feeding the ISO formatter.
        guard let firstDash = filename.range(of: "-", options: .backwards) else { return nil }
        // Find the timestamp prefix — everything up to the third hyphen-from-start
        // separating sender. Easier: locate the `Z` that terminates the timestamp.
        guard let zRange = filename.range(of: "Z") else { return nil }
        _ = firstDash
        let isoCandidate = String(filename[..<zRange.upperBound])
        // Convert `T20-15-00Z` → `T20:15:00Z`. Only the time portion has the
        // dashes-as-colons substitution; the date portion's dashes stay.
        var fixed = isoCandidate
        if let tIdx = fixed.firstIndex(of: "T") {
            let dateHead = fixed[..<tIdx]
            let timeTail = fixed[tIdx...]
            let timeFixed = String(timeTail).replacingOccurrences(of: "-", with: ":")
            fixed = String(dateHead) + timeFixed
        }
        return Self.iso8601.date(from: fixed)
    }

    // MARK: - Frontmatter rendering

    private func renderFrontmatter(
        from: String,
        category: String,
        urgency: FamilyMessage.Urgency,
        subject: String,
        status: FamilyMessage.ReadStatus,
        readAt: Date?,
        actionItems: [String],
        attachments: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("from: \(from)")
        lines.append("category: \(category)")
        lines.append("urgency: \(urgency.rawValue)")
        lines.append("subject: \(escapeForYaml(subject))")
        lines.append("status: \(status.rawValue)")
        if let readAt {
            lines.append("read_at: \(Self.iso8601.string(from: readAt))")
        } else {
            lines.append("read_at:")
        }
        if actionItems.isEmpty {
            lines.append("action_items: []")
        } else {
            lines.append("action_items:")
            for item in actionItems {
                lines.append("  - \(escapeForYaml(item))")
            }
        }
        if attachments.isEmpty {
            lines.append("attachments: []")
        } else {
            lines.append("attachments:")
            for path in attachments {
                lines.append("  - \(escapeForYaml(path))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quote strings that contain YAML-meaningful characters.
    private func escapeForYaml(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.contains("\n") || s.hasPrefix("-") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }

    /// Replace or add a single-line scalar field in a frontmatter string.
    /// Used by `markAsRead` so the rest of the file is preserved verbatim.
    private func upsertField(_ frontmatter: String, key: String, value: String) -> String {
        var lines = frontmatter.components(separatedBy: "\n")
        var found = false
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                lines[i] = "\(key): \(value)"
                found = true
                break
            }
        }
        if !found {
            // Insert before the trailing newline if any
            if lines.last?.isEmpty == true {
                lines.insert("\(key): \(value)", at: lines.count - 1)
            } else {
                lines.append("\(key): \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatter

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
