import SwiftUI
import Sparkle

// MARK: - Check for Updates View (Menu Bar Item)

struct CheckForUpdatesView: View {

    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self._viewModel = ObservedObject(
            initialValue: CheckForUpdatesViewModel(updater: updater)
        )
    }

    var body: some View {
        Button("Check for App Updates\u{2026}", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - View Model

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {

    @Published var canCheckForUpdates = false
    private nonisolated(unsafe) var timer: Timer?

    init(updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
