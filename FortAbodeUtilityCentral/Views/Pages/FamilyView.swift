import SwiftUI
import AlignedDesignSystem

// Phase 2b stub. Real Family page (Members directory, Health Dashboard,
// Shared Documents) lands in Phase 3.

struct FamilyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                EditorialHeader(eyebrow: "Kennedy Family", title: "Family")

                Text("Family page content lands in Phase 3.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.horizontal, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .padding(.bottom, Space.s24)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
