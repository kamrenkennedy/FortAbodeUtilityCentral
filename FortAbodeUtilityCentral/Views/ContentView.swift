import SwiftUI

// MARK: - Content View (Icon Gallery)

struct ContentView: View {

    @Environment(ComponentListViewModel.self) private var viewModel

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 24)
    ]

    var body: some View {
        ZStack {
            // Full-bleed glass background
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Icon grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(viewModel.components) { component in
                            ComponentCardView(
                                component: component,
                                status: viewModel.statuses[component.id] ?? .unknown
                            )
                        }
                    }
                    .padding(32)
                }

                Divider()
                    .opacity(0.3)

                // Bottom bar
                HStack {
                    Text(viewModel.lastCheckedText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if viewModel.availableUpdateCount > 0 {
                        Button {
                            Task { await viewModel.updateAll() }
                        } label: {
                            Label("Update All", systemImage: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.checkAll() }
                } label: {
                    Label("Check All", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isCheckingAll)
            }
        }
        .navigationTitle("Fort Abode Utility Central")
        .task {
            await viewModel.checkAll()
        }
    }
}

// MARK: - Visual Effect Background (translucent glass)

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
