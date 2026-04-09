import SwiftUI

// MARK: - Content View (Icon Gallery)

struct ContentView: View {

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var migrationName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 24)
    ]

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.installedComponents.isEmpty && !viewModel.isCheckingAll {
                        VStack(spacing: 16) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.secondary)

                            Text("No extensions installed")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            NavigationLink(value: AppDestination.marketplace) {
                                Label("Browse Marketplace", systemImage: "storefront")
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    } else {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(viewModel.installedComponents) { component in
                                NavigationLink(value: AppDestination.componentDetail(componentId: component.id)) {
                                    ComponentCardView(
                                        component: component,
                                        status: viewModel.statuses[component.id] ?? .unknown
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(32)
                    }
                }

                Divider()
                    .opacity(0.3)

                if viewModel.showRestartHint {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Restart Claude Desktop to activate new MCPs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") { viewModel.showRestartHint = false }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1))
                }

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
                HStack(spacing: 8) {
                    if !viewModel.marketplaceItems.isEmpty {
                        NavigationLink(value: AppDestination.marketplace) {
                            Label("Marketplace", systemImage: "storefront")
                        }
                    }

                    Button {
                        Task { await viewModel.checkAll() }
                    } label: {
                        Label("Check All", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isCheckingAll)
                }
            }
        }
        .navigationTitle("Fort Abode Utility Central")
        .task {
            await viewModel.checkAll()
        }
        .sheet(isPresented: Bindable(viewModel).memoryNeedsMigration) {
            MemoryMigrationSheet(name: $migrationName) {
                Task {
                    await viewModel.migrateMemoryKeys(displayName: migrationName)
                    migrationName = ""
                }
            }
        }
    }
}

// MARK: - Memory Migration Sheet

private struct MemoryMigrationSheet: View {
    @Binding var name: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.blue)

            Text("Personalize Your Memory")
                .font(.headline)

            Text("Your memory servers will be labeled with your name — for example, \"Tiera-Memory\" instead of a generic label.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Your first name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Button("Update Labels") {
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(32)
        .frame(width: 340)
    }
}

// MARK: - Visual Effect Background

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
