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

    init(speaker: Speaker, text: String, actionChips: [String] = []) {
        self.speaker = speaker
        self.text = text
        self.actionChips = actionChips
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
