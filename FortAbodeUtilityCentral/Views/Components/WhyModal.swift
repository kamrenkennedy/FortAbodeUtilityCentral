import SwiftUI
import AlignedDesignSystem

// MARK: - WhyModal
//
// Surface 6 from the parity-pass design package — explains the engine's
// reasoning for an item it proposed (event / reminder / proposal). Opens
// from a Why? affordance on engine-proposed rows.
//
// Spec: .claude/design/v4-parity-pass/README.md §6
//
// Width 520pt. Header eyebrow includes the item kind ("WHY THIS · PROPOSAL"
// / "WHY THIS · EVENT"). Body: editorial single-column narrative. Footer
// leading: "Edit instead →" deep-link (closes Why?, opens Edit modal for
// the same item). Footer trailing: Close.

struct WhyContext: Identifiable, Equatable {
    public enum Kind: String { case proposal, event, reminder }
    public let id: String        // item id
    public let kind: Kind
    public let title: String
    public let paragraphs: [String]
    public let confidence: String      // "0.82"
    public let source: String          // "memory · 6w window · 12 events"

    public init(
        id: String,
        kind: Kind,
        title: String,
        paragraphs: [String],
        confidence: String = "—",
        source: String = "—"
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.paragraphs = paragraphs
        self.confidence = confidence
        self.source = source
    }
}

struct WhyModal: View {
    let context: WhyContext
    let onEditInstead: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        AlignedSheet(
            eyebrow: "Why this · \(context.kind.rawValue)",
            title: context.title,
            idealWidth: 520,
            onDismiss: onDismiss,
            content: { whyBody },
            footer: { footer }
        )
    }

    // MARK: - Body

    private var whyBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ForEach(Array(context.paragraphs.enumerated()), id: \.offset) { offset, paragraph in
                Text(paragraph)
                    .font(.bodyLG)
                    .foregroundStyle(offset == 0 ? Color.onSurface : Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            confidenceCard
                .padding(.top, Space.s2)
        }
    }

    private var confidenceCard: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("CONFIDENCE")
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.onSurfaceVariant)
                Text(context.confidence)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text("SOURCE")
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.onSurfaceVariant)
                Text(context.source)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            Button {
                onEditInstead()
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Text("Edit instead")
                        .font(.labelLG.weight(.medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.tertiaryBright)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Close", action: onDismiss)
                .buttonStyle(.alignedPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }
}
