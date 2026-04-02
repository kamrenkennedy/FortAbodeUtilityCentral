import SwiftUI

// MARK: - Update Progress View (Terminal handoff overlay)

struct UpdateProgressView: View {

    @Environment(ComponentListViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Update running in Terminal")
                .font(.headline)

            Text("The update is running in a Terminal window. When it finishes, click below to re-check versions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Done — Re-check Versions") {
                Task { await viewModel.checkAll() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
