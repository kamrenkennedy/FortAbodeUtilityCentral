import Foundation

// File-backed messaging between Kam and Tiera. Each `.md` file in
// `Kennedy Family Docs/Weekly Rhythm/{user}/messages/inbox/` is one message,
// with YAML-ish frontmatter + a markdown body. The protocol is defined in
// the Weekly Rhythm engine spec (Step 5h + Step 12b).
//
// Filename: `{ISO-timestamp}-{sender}-{category}.md`
//   e.g. `2026-04-30T20-15-00Z-Kamren-update.md`
// (colons are illegal on case-insensitive HFS+; the format substitutes
// dashes for the time-portion colons.)
//
// Frontmatter (block delimited by `---` lines, parsed line-by-line — we
// don't pull in a full YAML decoder for a dozen scalar fields):
//   from: Kamren
//   category: update
//   urgency: normal
//   subject: New shoot date locked
//   status: unread
//   read_at:                   # nil when unread; ISO timestamp when read
//   action_items:
//     - "Confirm with Tiera by Wed"
//
// Cross-Mac sync: both Macs see both `Kamren/` and `Tiera/` folders via
// iCloud Folder Sharing. A "send to Tiera" writes a file into
// `Tiera/messages/inbox/`; on Tiera's Mac the same path is her inbox.
// FamilyChatPane reads BOTH sides' inboxes and merges them so the
// conversation reads as a chat regardless of which Mac sent which message.

struct FamilyMessage: Identifiable, Hashable, Sendable {
    let id: String                  // = filename without .md extension
    let filename: String
    let absolutePath: String        // for in-place mark-as-read writes
    let from: String                // "Kamren" / "Tiera"
    let recipient: String           // computed from which inbox the file is in
    let category: String
    let urgency: Urgency
    let subject: String
    let status: ReadStatus
    let readAt: Date?
    let actionItems: [String]
    let body: String
    let timestamp: Date             // parsed from filename's ISO prefix
    /// Resolved absolute file URLs for attachments referenced by this
    /// message's frontmatter. Empty when no attachments. Hydrated from the
    /// frontmatter's relative paths against the message's inbox directory
    /// at parse time so views can use them directly without re-resolving.
    let attachments: [URL]

    enum Urgency: String, Codable, Sendable, CaseIterable, Hashable {
        case low, normal, high
    }

    enum ReadStatus: String, Codable, Sendable, Hashable {
        case unread, read
    }
}

// MARK: - Composing a new message
//
// Used by the chat composer to hand a draft to FamilyMessagesService.send.
// Distinct from `FamilyMessage` because a draft has no filename / timestamp /
// path / status yet — those are set when the service writes the file.

struct FamilyMessageDraft: Sendable {
    let category: String
    let urgency: FamilyMessage.Urgency
    let subject: String
    let body: String
    let actionItems: [String]
    /// Local file URLs to be copied into the partner's per-message attachments
    /// directory when the message is sent. The service reads each file once
    /// at send time; the originals can move or be deleted afterward.
    let attachments: [URL]

    init(
        subject: String,
        body: String,
        category: String = "update",
        urgency: FamilyMessage.Urgency = .normal,
        actionItems: [String] = [],
        attachments: [URL] = []
    ) {
        self.subject = subject
        self.body = body
        self.category = category
        self.urgency = urgency
        self.actionItems = actionItems
        self.attachments = attachments
    }
}
