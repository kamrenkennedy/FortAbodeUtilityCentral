import SwiftUI
import AlignedDesignSystem

// MARK: - AlignedSheet
//
// Card-floating modal baseline matching `DashboardCard` aesthetics. Replaces
// SwiftUI's default `.sheet(item:)` chrome (square corners, system toolbar)
// with the editorial style shipped across Home / Family / Weekly Rhythm /
// Marketplace tabs.
//
// Slot composition:
//   • Header   — eyebrow + title + optional trailing badge + close X (28pt)
//   • Body     — primary content; scrolls when content overflows
//   • Footer   — surfaceContainerLow bg, 1pt outlineVariant top border;
//                trailing area for primary + secondary action buttons,
//                leading area for tertiary actions (Delete / Mark complete /
//                hint text).
//
// Sizing (from design package §1):
//   • minWidth 480, idealWidth 560 (forms) / 720 (2-col edit) / 620 (run health)
//   • Max height respects screen; body scrolls when content overflows.
//
// Usage:
//   AlignedSheet(
//       eyebrow: "Edit event",
//       title: event.title,
//       idealWidth: 760,
//       onDismiss: { selection = nil },
//       content: { /* form fields */ },
//       footer:  { /* Cancel + Save */ }
//   )
//
// Spec: .claude/design/v4-parity-pass/README.md §1
// Note: prop name is `content` (not `body`) to avoid clashing with SwiftUI's
// required `body: some View` requirement.

public struct AlignedSheet<Content: View, Footer: View>: View {
    public let eyebrow: String
    public let title: String
    public let badge: AnyView?
    public let idealWidth: CGFloat
    public let onDismiss: () -> Void
    @ViewBuilder public let content: () -> Content
    @ViewBuilder public let footer: () -> Footer

    public init(
        eyebrow: String,
        title: String,
        badge: AnyView? = nil,
        idealWidth: CGFloat = 560,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.badge = badge
        self.idealWidth = idealWidth
        self.onDismiss = onDismiss
        self.content = content
        self.footer = footer
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color.outlineVariant)
                .frame(height: 1)

            ScrollView {
                content()
                    .padding(.horizontal, Space.s8)
                    .padding(.vertical, Space.s6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Rectangle()
                .fill(Color.outlineVariant)
                .frame(height: 1)

            footerBar
        }
        .frame(minWidth: 480, idealWidth: idealWidth, maxWidth: 880)
        .frame(maxHeight: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Color.outlineVariant, lineWidth: 1)
        )
        .floatingPanelShadow()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(eyebrow.uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)

                Text(title)
                    .font(.displaySM)
                    .kerning(-0.4)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let badge { badge }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color.surfaceContainerHigh)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.top, Space.s6)
        .padding(.horizontal, Space.s8)
        .padding(.bottom, Space.s5)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: Space.s3) {
            footer()
        }
        .padding(.horizontal, Space.s8)
        .padding(.vertical, Space.s4)
        .background(Color.surfaceContainerLow)
    }
}

// MARK: - Convenience overload — no badge, only content + footer

public extension AlignedSheet {
    init(
        eyebrow: String,
        title: String,
        idealWidth: CGFloat = 560,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            badge: nil,
            idealWidth: idealWidth,
            onDismiss: onDismiss,
            content: content,
            footer: footer
        )
    }
}
