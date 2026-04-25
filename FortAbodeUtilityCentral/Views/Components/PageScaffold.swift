import SwiftUI
import AlignedDesignSystem

// Shared scaffolding for v4.0.0 dashboard pages.
// - SectionEyebrow: uppercase eyebrow above a section, with optional trailing
//   text or "View all →" link.
// - DashboardCard: rounded card with surface-container-lowest background and
//   whisper shadow. Optional hover lift (translateY -2pt on hover).
// - RowSeparator: hairline divider between rows inside a card (outline-variant
//   at 18% opacity per HTML spec).

struct SectionEyebrow: View {
    let text: String
    var trailing: String? = nil
    var trailingLink: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.labelSM)
                .tracking(2.0)
                .foregroundStyle(Color.secondaryText)

            Spacer(minLength: Space.s2)

            if let trailing {
                Text(trailing)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            } else if let trailingLink, let trailingAction {
                Button(action: trailingAction) {
                    Text(trailingLink)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DashboardCard<Content: View>: View {
    let isHoverable: Bool
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    let content: () -> Content

    init(
        isHoverable: Bool = false,
        verticalPadding: CGFloat = Space.s2,
        horizontalPadding: CGFloat = Space.s6,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isHoverable = isHoverable
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    @State private var isHovering = false

    var body: some View {
        content()
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .offset(y: (isHoverable && isHovering) ? -2 : 0)
            .animation(.easeOut(duration: 0.2), value: isHovering)
            .whisperShadow()
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.18))
            .frame(height: 1)
    }
}
