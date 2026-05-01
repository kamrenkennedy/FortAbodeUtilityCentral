import SwiftUI
import AlignedDesignSystem

// Family DMs — Kam ↔ Tiera. File-backed via FamilyMessagesService:
// reads both inboxes (active user's + partner's) from the shared iCloud
// folder so the conversation is reconstructed regardless of which Mac
// originated each message. Composer onSend writes a new .md to the
// partner's inbox.

struct FamilyChatPane: View {
    @State private var draft: String = ""
    @State private var messages: [FamilyMessage] = []
    @State private var partnerName: String?
    @State private var sendError: String?
    @State private var isSending = false

    private let service = FamilyMessagesService()

    var body: some View {
        VStack(spacing: 0) {
            messagesScroll
            if let err = sendError {
                errorBar(err)
            }
            composer
        }
        .task {
            await load()
            partnerName = await service.partnerUserName(activeUser: FamilyMessagesService.activeUserName())
        }
    }

    private var messagesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if messages.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedByDay, id: \.label) { group in
                        dayDivider(group.label)
                        ForEach(group.messages) { msg in
                            messageRow(msg)
                                .onAppear {
                                    markAsReadIfNeeded(msg)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(emptyStateTitle)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
            Text(emptyStateSubtitle)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s4)
    }

    private var emptyStateTitle: String {
        if let partnerName {
            return "No messages with \(partnerName) yet"
        }
        return "No messages yet"
    }

    private var emptyStateSubtitle: String {
        if partnerName != nil {
            return "Send the first one below — it'll land in their Family inbox via shared iCloud."
        }
        return "Family messaging needs a second user folder under Weekly Rhythm/. Once it's there, messages route automatically."
    }

    @ViewBuilder
    private func messageRow(_ msg: FamilyMessage) -> some View {
        // The active user's outgoing messages render right-aligned; partner's
        // render left-aligned. `from` is the canonical source (don't infer
        // from inbox path — file-system folder doesn't tell us authorship).
        let isOutgoing = msg.from == FamilyMessagesService.activeUserName()
        let speaker: MessageBubble.Speaker = isOutgoing ? .user : .tiera
        let prefix = msg.subject.isEmpty || msg.subject == "(no subject)"
            ? ""
            : "\(msg.subject)\n"
        let text = (prefix + msg.body).isEmpty ? "(empty message)" : prefix + msg.body
        MessageBubble(
            speaker: speaker,
            text: text,
            actionChips: msg.actionItems
        )
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: Space.s2) {
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
            Text(label.uppercased())
                .font(.labelSM)
                .tracking(1.5)
                .foregroundStyle(Color.onSurfaceVariant)
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func errorBar(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)
            Text(message)
                .font(.bodySM)
                .foregroundStyle(Color.onSurface)
            Spacer(minLength: Space.s2)
            Button("Dismiss") { sendError = nil }
                .buttonStyle(.plain)
                .font(.labelSM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(Color.statusError.opacity(0.08))
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            ChatComposer(
                text: $draft,
                placeholder: composerPlaceholder,
                leadingIcons: [
                    ComposerIconButton(symbol: "calendar", help: "Insert event", action: {}),
                    ComposerIconButton(symbol: "checkmark.circle", help: "Insert errand", action: {}),
                    ComposerIconButton(symbol: "paperclip", help: "Attach", action: {})
                ],
                onSend: { text in
                    Task { await sendDraft(text) }
                }
            )
            .padding(Space.s3)
        }
    }

    private var composerPlaceholder: String {
        partnerName.map { "Message \($0)…" } ?? "Message your partner…"
    }

    // MARK: - Day grouping

    private struct DayGroup {
        let label: String
        let messages: [FamilyMessage]
    }

    private var groupedByDay: [DayGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var groups: [(Date, [FamilyMessage])] = []
        for msg in messages {
            let day = cal.startOfDay(for: msg.timestamp)
            if let last = groups.last, last.0 == day {
                groups[groups.count - 1].1.append(msg)
            } else {
                groups.append((day, [msg]))
            }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMM d"
        return groups.map { (day, msgs) in
            let label: String
            if day == today {
                label = "Today"
            } else if let yesterday = cal.date(byAdding: .day, value: -1, to: today), day == yesterday {
                label = "Yesterday"
            } else {
                label = formatter.string(from: day)
            }
            return DayGroup(label: label, messages: msgs)
        }
    }

    // MARK: - Actions

    private func load() async {
        let convo = await service.loadConversation()
        await MainActor.run {
            self.messages = convo
        }
    }

    private func markAsReadIfNeeded(_ msg: FamilyMessage) {
        // Only inbound + unread messages need marking. Outbound messages live
        // in the partner's inbox; the partner's Mac handles those when they
        // open the pane on their side.
        let active = FamilyMessagesService.activeUserName()
        guard msg.recipient == active, msg.status == .unread else { return }
        Task {
            await service.markAsRead(msg)
            // Refresh state so the row reflects the new status. Cheap — file
            // re-read is local I/O.
            await load()
        }
    }

    private func sendDraft(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            // Default category is "update" — future iterations can offer a
            // picker on the leading icon row to pick errand / question / etc.
            let draft = FamilyMessageDraft(subject: "", body: trimmed)
            let sent = try await service.send(draft: draft)
            await MainActor.run {
                messages.append(sent)
                sendError = nil
            }
        } catch {
            await MainActor.run {
                sendError = error.localizedDescription
            }
        }
    }
}
