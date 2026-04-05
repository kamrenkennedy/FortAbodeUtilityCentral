import SwiftUI

// MARK: - Family Activation View

/// Shown on first launch before the user has activated with the family code.
/// Once activated, the code is stored in Keychain and this view never appears again.
struct ActivationView: View {

    @State private var code = ""
    @State private var isShaking = false
    @State private var showError = false
    @State private var isActivating = false

    /// Called when activation succeeds
    var onActivated: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // App icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

                VStack(spacing: 8) {
                    Text("Fort Abode Utility Central")
                        .font(.title.bold())

                    Text("Enter your family activation code to get started.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                // Code input
                VStack(spacing: 12) {
                    SecureField("Activation Code", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onSubmit { activate() }
                        .offset(x: isShaking ? -8 : 0)

                    if showError {
                        Text("Invalid code. Please try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    }
                }

                Button(action: activate) {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 120)
                    } else {
                        Text("Activate")
                            .frame(width: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(code.isEmpty || isActivating)
                .keyboardShortcut(.defaultAction)

                Spacer()

                Text("This app is for authorized family members only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
            .padding(40)
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func activate() {
        isActivating = true
        showError = false

        // Small delay for feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if KeychainService.activate(with: code) {
                withAnimation(.easeOut(duration: 0.2)) {
                    onActivated()
                }
            } else {
                showError = true
                // Shake animation
                withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) {
                    isShaking = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isShaking = false
                }
                code = ""
            }
            isActivating = false
        }
    }
}
