import SwiftUI
import AlignedDesignSystem

// Pill-shaped composer for the chat panel. Used by both the Family and Claude
// panes. Leading/trailing icon slots vary per pane (insert-event/errand on
// Family; attach/tools/voice + Sonnet model badge on Claude).

struct ChatComposer: View {
    @Binding var text: String
    let placeholder: String
    let leadingIcons: [ComposerIconButton]
    let trailingIcons: [ComposerIconButton]
    let trailingTrailing: AnyView?  // optional pre-send slot, e.g. Sonnet badge
    let onSend: (String) -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        leadingIcons: [ComposerIconButton] = [],
        trailingIcons: [ComposerIconButton] = [],
        trailingTrailing: AnyView? = nil,
        onSend: @escaping (String) -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.leadingIcons = leadingIcons
        self.trailingIcons = trailingIcons
        self.trailingTrailing = trailingTrailing
        self.onSend = onSend
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(leadingIcons) { $0 }

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.bodyMD)
                .lineLimit(1...4)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, Space.s1_5)
                .onSubmit(send)

            ForEach(trailingIcons) { $0 }

            if let trailingTrailing {
                trailingTrailing
            }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(text.isEmpty ? Color.outlineVariant : Color.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1_5)
        .background(
            Capsule()
                .fill(Color.surfaceContainer)
        )
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

struct ComposerIconButton: View, Identifiable {
    let id = UUID()
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
