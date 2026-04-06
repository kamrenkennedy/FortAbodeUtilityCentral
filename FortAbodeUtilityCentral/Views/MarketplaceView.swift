import SwiftUI

// MARK: - Marketplace View

struct MarketplaceView: View {

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var wizardComponent: Component?

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            ScrollView {
                if viewModel.marketplaceItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.green)

                        Text("Everything is installed")
                            .font(.headline)

                        Text("All available extensions are already on this machine.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    VStack(spacing: 16) {
                        ForEach(viewModel.marketplaceItems) { component in
                            marketplaceCard(component)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Marketplace")
        .sheet(item: $wizardComponent) { component in
            SetupWizardView(
                viewModel: SetupWizardViewModel(component: component),
                onComplete: { inputs in
                    Task { await viewModel.installComponentWithInputs(component.id, inputs: inputs) }
                }
            )
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func marketplaceCard(_ component: Component) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }

                Image(systemName: component.iconName)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 56, height: 56)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(component.displayName)
                    .font(.headline)

                Text(component.userDescription ?? component.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Install button or progress
            let status = viewModel.statuses[component.id] ?? .notInstalled

            if status == .updating {
                ProgressView()
                    .controlSize(.small)
            } else if case .error(let msg) = status {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            } else {
                Button {
                    if component.requiresSetup {
                        wizardComponent = component
                    } else {
                        Task { await viewModel.installComponent(component.id) }
                    }
                } label: {
                    Text("Install")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
