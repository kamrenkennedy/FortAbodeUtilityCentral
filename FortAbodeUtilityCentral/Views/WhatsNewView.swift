import SwiftUI

// MARK: - What's New View (Post-Update Splash)

struct WhatsNewView: View {

    let version: String
    let notes: [String]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Hey Honey")
                    .font(.system(size: 28, weight: .bold))

                Text("Here's what's new in this update")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("v\(version)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.8))
                    .padding(.top, 4)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
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
        guard let url = Bundle.main.url(forResource: "whats-new", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? JSONDecoder().decode([WhatsNewRelease].self, from: data) else {
            return nil
        }
        return releases.first { $0.version == version }
    }
}
