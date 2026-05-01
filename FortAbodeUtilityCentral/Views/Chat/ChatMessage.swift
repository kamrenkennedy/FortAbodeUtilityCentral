import SwiftUI
import AlignedDesignSystem

// Message rendering for the chat panel. Two surfaces:
// - MessageBubble: a plain text message (user/tiera/claude variants)
// - RichCardMessage: an event/errand/proposal card with optional Accept/Decline

struct MessageBubble: View {
    enum Speaker {
        case user
        case tiera
        case claude
    }

    let speaker: Speaker
    let text: String
    let actionChips: [String]
    let attachments: [URL]

    init(speaker: Speaker, text: String, actionChips: [String] = [], attachments: [URL] = []) {
        self.speaker = speaker
        self.text = text
        self.actionChips = actionChips
        self.attachments = attachments
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s2) {
            if speaker != .user {
                avatar
            } else {
                Spacer(minLength: Space.s10)
            }

            VStack(alignment: alignment, spacing: Space.s1_5) {
                Text(text)
                    .font(.bodyMD)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2_5)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                            .fill(bubbleColor)
                    )

                if !attachments.isEmpty {
                    VStack(alignment: alignment, spacing: Space.s1) {
                        ForEach(attachments, id: \.self) { url in
                            AttachmentChip(url: url)
                        }
                    }
                }

                if !actionChips.isEmpty {
                    HStack(spacing: Space.s1_5) {
                        ForEach(actionChips, id: \.self) { chip in
                            ActionChip(chip)
                        }
                    }
                }
            }

            if speaker == .user {
                // No avatar — Kam is the implicit "self"
            } else {
                Spacer(minLength: Space.s10)
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(avatarFill)
            .frame(width: 28, height: 28)
            .overlay(avatarGlyph)
    }

    @ViewBuilder
    private var avatarGlyph: some View {
        switch speaker {
        case .tiera:
            Text("T")
                .font(.labelMD)
                .foregroundStyle(Color.onTertiary)
        case .claude:
            Image(systemName: "asterisk")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.onSurface)
        case .user:
            EmptyView()
        }
    }

    private var avatarFill: Color {
        switch speaker {
        case .tiera:  return Color.tertiary
        case .claude: return Color.surfaceContainerHigh
        case .user:   return .clear
        }
    }

    private var alignment: HorizontalAlignment {
        speaker == .user ? .trailing : .leading
    }

    private var textColor: Color {
        speaker == .user ? Color.onTertiary : Color.onSurface
    }

    private var bubbleColor: Color {
        speaker == .user ? Color.tertiary : Color.surfaceContainer
    }
}

/// One attachment row beneath a message bubble. Tap opens the file with the
/// system's default handler (NSWorkspace.shared.open). For images, embeds a
/// small inline preview above the chip; for everything else, just an icon.
struct AttachmentChip: View {
    let url: URL

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 200, maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                HStack(spacing: Space.s1_5) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.onSurfaceVariant)
                    Text(url.lastPathComponent)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, Space.s2)
                .padding(.vertical, Space.s1_5)
                .background(
                    Capsule().fill(Color.surfaceContainer)
                )
            }
        }
        .buttonStyle(.plain)
        .help("Open \(url.lastPathComponent)")
        .onAppear(perform: loadThumbnailIfImage)
    }

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "pdf":                                            return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "webp":      return "photo"
        case "mp4", "mov", "m4v":                              return "play.rectangle"
        case "mp3", "m4a", "wav":                              return "speaker.wave.2"
        case "md", "txt":                                      return "doc.text"
        case "zip":                                            return "archivebox"
        default:                                               return "paperclip"
        }
    }

    private func open() {
        NSWorkspace.shared.open(url)
    }

    private func loadThumbnailIfImage() {
        guard ["png", "jpg", "jpeg", "heic", "webp", "gif"]
                .contains(url.pathExtension.lowercased()) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                thumbnail = image
            }
        }
    }
}

// Y6 Phase 5c.2: Plan Card. Renders Claude's drafted plan (from
// `--permission-mode plan`) with Execute and Cancel buttons. Execute
// re-runs the originating prompt in `.allowlist` mode so the plan
// actually gets carried out; Cancel just dismisses the buttons.
struct PlanCardMessage: View {
    let plan: String
    let onExecute: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Circle()
                .fill(Color.tertiary.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.tertiary)
                )

            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s1) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("PLAN PREVIEW")
                        .font(.labelSM)
                        .tracking(1.5)
                }
                .foregroundStyle(Color.tertiary)

                Text(plan)
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: Space.s2) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .font(.labelMD)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s1_5)
                    Button("Execute", action: onExecute)
                        .buttonStyle(.plain)
                        .font(.labelMD.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s1_5)
                        .background(
                            Capsule().fill(Color.brandRust)
                        )
                }
                .padding(.top, Space.s1)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                    .fill(Color.surfaceContainer)
            )

            Spacer(minLength: Space.s10)
        }
    }
}

struct RichCardMessage: View {
    let kicker: String
    let kickerSymbol: String
    let title: String
    let meta: String
    let acceptLabel: String?
    let declineLabel: String?
    let onAccept: (() -> Void)?
    let onDecline: (() -> Void)?

    init(
        kicker: String,
        kickerSymbol: String,
        title: String,
        meta: String,
        acceptLabel: String? = nil,
        declineLabel: String? = nil,
        onAccept: (() -> Void)? = nil,
        onDecline: (() -> Void)? = nil
    ) {
        self.kicker = kicker
        self.kickerSymbol = kickerSymbol
        self.title = title
        self.meta = meta
        self.acceptLabel = acceptLabel
        self.declineLabel = declineLabel
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s1) {
                Image(systemName: kickerSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(kicker.uppercased())
                    .font(.labelSM)
                    .tracking(1.5)
            }
            .foregroundStyle(Color.tertiary)

            Text(title)
                .font(.headlineSM)
                .foregroundStyle(Color.onSurface)

            Text(meta)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)

            if onAccept != nil || onDecline != nil {
                HStack(spacing: Space.s2) {
                    if let declineLabel, let onDecline {
                        Button(declineLabel, action: onDecline)
                            .buttonStyle(.plain)
                            .font(.labelMD)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s1_5)
                    }
                    if let acceptLabel, let onAccept {
                        Button(acceptLabel, action: onAccept)
                            .buttonStyle(.plain)
                            .font(.labelMD)
                            .foregroundStyle(Color.onTertiary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s1_5)
                            .background(
                                Capsule()
                                    .fill(Color.tertiary)
                            )
                    }
                }
                .padding(.top, Space.s1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                .fill(Color.surfaceContainer)
        )
    }
}
