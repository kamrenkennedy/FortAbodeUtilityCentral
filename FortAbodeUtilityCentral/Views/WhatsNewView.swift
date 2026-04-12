import SwiftUI

// MARK: - What's New View (Post-Update Splash)

struct WhatsNewView: View {

    let releases: [WhatsNewRelease]
    let onDismiss: () -> Void

    /// Convenience for a single release
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
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Hey Honey")
                        .font(.system(size: 28, weight: .bold))

                    Text(releases.count > 1
                         ? "Here's what you missed"
                         : "Here's what's new in this update")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                Divider()
                    .padding(.horizontal, 32)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(releases) { release in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("v\(release.version)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.8))

                                ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.blue)
                                            .padding(.top, 3)

                                        Text(note)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if release.id != releases.last?.id {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 20)
                }

                Divider()
                    .padding(.horizontal, 32)

                Button("Got It") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 380)
        .frame(minHeight: 340)
    }
}

// MARK: - What's New Data

struct WhatsNewRelease: Codable, Identifiable {
    let version: String
    let notes: [String]

    var id: String { version }
}

enum WhatsNewLoader {

    /// Load release notes from the bundled whats-new.json for the given version.
    /// Returns nil if no entry exists for that version.
    static func load(for version: String) -> WhatsNewRelease? {
        guard let releases = loadAll() else { return nil }
        return releases.first { $0.version == version }
    }

    /// Load all releases between lastSeen (exclusive) and current (inclusive),
    /// sorted newest-first. Returns nil if no entries match.
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
