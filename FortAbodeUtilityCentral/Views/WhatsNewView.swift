import SwiftUI
import AlignedDesignSystem

// MARK: - What's New View (Post-Update Splash)
//
// v4.0.0 restyle: token-swap pass, Manrope display title, brandRust sparkle
// glyph (notification accent), primaryFill "Got It" CTA.

struct WhatsNewView: View {

    let releases: [WhatsNewRelease]
    let onDismiss: () -> Void

    init(version: String, notes: [String], onDismiss: @escaping () -> Void) {
        self.releases = [WhatsNewRelease(version: version, notes: notes)]
        self.onDismiss = onDismiss
    }

    init(releases: [WhatsNewRelease], onDismiss: @escaping () -> Void) {
        self.releases = releases
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: Space.s1_5) {
                    Text("Hey Honey")
                        .font(.displaySM)
                        .foregroundStyle(Color.onSurface)

                    Text(releases.count > 1
                         ? "Here's what you missed"
                         : "Here's what's new in this update")
                        .font(.bodyMD)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s5)

                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, Space.s8)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s5) {
                        ForEach(releases) { release in
                            VStack(alignment: .leading, spacing: Space.s3) {
                                Text("v\(release.version)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.statusScheduled)

                                ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                                    HStack(alignment: .top, spacing: Space.s2_5) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.brandRust)
                                            .padding(.top, 3)

                                        Text(note)
                                            .font(.bodyMD)
                                            .foregroundStyle(Color.onSurface)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if release.id != releases.last?.id {
                                Rectangle()
                                    .fill(Color.outlineVariant.opacity(0.18))
                                    .frame(height: 1)
                                    .padding(.vertical, Space.s1)
                            }
                        }
                    }
                    .padding(.horizontal, Space.s8)
                    .padding(.vertical, Space.s5)
                }

                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, Space.s8)

                Button(action: onDismiss) {
                    Text("Got It")
                        .font(.labelLG.weight(.semibold))
                        .foregroundStyle(Color.onPrimary)
                        .frame(width: 120, height: 24)
                }
                .padding(.vertical, Space.s2)
                .background(
                    Capsule()
                        .fill(Color.primaryFill)
                )
                .buttonStyle(.plain)
                .ctaShadow()
                .padding(.vertical, Space.s5)
            }
        }
        .frame(width: 420)
        .frame(minHeight: 360)
    }
}

// MARK: - What's New Data

struct WhatsNewRelease: Codable, Identifiable {
    let version: String
    let notes: [String]

    var id: String { version }
}

enum WhatsNewLoader {

    static func load(for version: String) -> WhatsNewRelease? {
        guard let releases = loadAll() else { return nil }
        return releases.first { $0.version == version }
    }

    static func loadSince(lastSeen: String, current: String) -> [WhatsNewRelease]? {
        guard let releases = loadAll() else { return nil }

        let matching = releases.filter { release in
            release.version.compare(lastSeen, options: .numeric) == .orderedDescending &&
            release.version.compare(current, options: .numeric) != .orderedDescending
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }

        return matching.isEmpty ? nil : matching
    }

    private static func loadAll() -> [WhatsNewRelease]? {
        guard let url = Bundle.main.url(forResource: "whats-new", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? JSONDecoder().decode([WhatsNewRelease].self, from: data) else {
            return nil
        }
        return releases
    }
}
