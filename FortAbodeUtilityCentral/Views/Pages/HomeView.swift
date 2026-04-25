import SwiftUI
import AlignedDesignSystem

// Phase 2b stub. Real Home page (Family Vitals, Triage, This Week, Marketplace
// Pulse) lands in Phase 3.

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                EditorialHeader(eyebrow: "Family Dashboard", title: todaysTitle)

                Text("Home page content lands in Phase 3.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.horizontal, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .padding(.bottom, Space.s24)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var todaysTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        return "Today, \(formatter.string(from: Date()))"
    }
}
