import SwiftUI
import AlignedDesignSystem

// MARK: - Run Health Pill (engine-spec.md run health diagnostic)
//
// Compact status pill — green checkmark for healthy runs, amber warning, red
// error. Lifted out of `WeeklyRhythmView.swift` (Phase 6) so the new
// `WeeklyRhythmRunControl` widget can compose it next to the run + schedule
// controls without duplicating the pill chrome.

struct RunHealthPill: View {
    enum State: Sendable, Equatable {
        case allGood
        case warning(String)
        case error(String)
    }

    let state: State

    var body: some View {
        HStack(spacing: Space.s1_5) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.labelMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1_5)
        .background(
            Capsule()
                .fill(Color.surfaceContainerHigh)
        )
    }

    private var glyph: String {
        switch state {
        case .allGood: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .allGood: return Color.statusScheduled
        case .warning: return Color.statusDraft
        case .error:   return Color.statusError
        }
    }

    private var label: String {
        switch state {
        case .allGood:                 return "All good"
        case .warning(let message):    return message
        case .error(let message):      return message
        }
    }
}
