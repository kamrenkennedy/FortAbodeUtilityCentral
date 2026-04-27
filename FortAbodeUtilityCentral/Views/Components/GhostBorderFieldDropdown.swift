import SwiftUI
import AlignedDesignSystem

// MARK: - GhostBorderFieldDropdown
//
// Companion to `AlignedDesignSystem.GhostBorderField` for cases where the
// value comes from a fixed option set (e.g. Day = Monday/Tuesday/...).
// Same visual treatment — uppercased eyebrow label + value + animated
// underline — but the value cell is a `Menu` instead of a `TextField`.
//
// Used by the v4.x parity edit modals (`EditEventSheet`, `EditTriageSheet`)
// for fields where free-text would be wrong: weekday, type tag,
// disposition, etc.
//
// Lives in Fort Abode local Components/ rather than AlignedDesignSystem
// because the package-side dropdown story is a bigger design exercise; this
// is a narrow, app-specific helper that we'll promote later if it gets
// reused outside Fort Abode.

struct GhostBorderFieldDropdown: View {
    let label: String
    @Binding var value: String
    let options: [String]
    let placeholder: String

    init(
        label: String,
        value: Binding<String>,
        options: [String],
        placeholder: String = ""
    ) {
        self.label = label
        self._value = value
        self.options = options
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label.uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { value = opt }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    Text(value.isEmpty ? placeholder : value)
                        .font(.bodyLG)
                        .foregroundStyle(value.isEmpty ? Color.onSurfaceVariant : Color.onSurface)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(.vertical, Space.s1)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.outlineVariant)
                .frame(height: 1)
        }
    }
}
