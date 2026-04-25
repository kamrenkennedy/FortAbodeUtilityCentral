import SwiftUI
import AlignedDesignSystem

// Phase 2b stub. Real Weekly Rhythm page (Project Pulse, Week Grid, Triage,
// Confirm bar) lands in Phase 3 — translated from existing
// Resources/dashboard-template.html structure.

struct WeeklyRhythmView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                EditorialHeader(eyebrow: "Week 17", title: "April 21 — 27")

                Text("Weekly Rhythm content lands in Phase 3.")
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
