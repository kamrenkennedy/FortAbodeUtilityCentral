import SwiftUI
import AlignedDesignSystem

// Sidebar bottom card — the "Kennedy Family" identity. Avatar circle in
// tertiary fill + name + email row. Hidden when the sidebar is collapsed.

struct KennedyFamilyIdentityCard: View {
    var body: some View {
        HStack(spacing: Space.s3) {
            Circle()
                .fill(Color.tertiary)
                .frame(width: 32, height: 32)
                .overlay(
                    Text("K")
                        .font(.labelLG)
                        .foregroundStyle(Color.onTertiary)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text("Kennedy Family")
                    .font(.labelLG)
                    .foregroundStyle(Color.onSurface)
                Text("kam@kamstudios.com")
                    .font(.labelSM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
    }
}
