import SwiftUI
import AppKit
import AlignedDesignSystem

// MARK: - Family Activation View
//
// First-launch gate. Once activated, the code is stored in Keychain and this
// view never appears again. v4.0.0 restyle: token-swap pass, primaryFill CTA,
// GhostBorderField pattern for the code input.

struct ActivationView: View {

    @State private var code = ""
    @State private var isShaking = false
    @State private var showError = false
    @State private var isActivating = false

    var onActivated: () -> Void

    var body: some View {
        ZStack {
            Color.surface
                .ignoresSafeArea()

            VStack(spacing: Space.s8) {
                Spacer()

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

                VStack(spacing: Space.s2) {
                    Text("Fort Abode Utility Central")
                        .font(.headlineLG)
                        .foregroundStyle(Color.onSurface)

                    Text("Enter your family activation code to get started.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Space.s3) {
                    SecureField("Activation Code", text: $code)
                        .textFieldStyle(.plain)
                        .font(.bodyLG)
                        .foregroundStyle(Color.onSurface)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(Color.surfaceContainerLow)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(Color.outlineVariant.opacity(0.4), lineWidth: 1)
                        )
                        .frame(maxWidth: 320)
                        .onSubmit { activate() }
                        .offset(x: isShaking ? -8 : 0)

                    if showError {
                        Text("Invalid code. Please try again.")
                            .font(.labelMD)
                            .foregroundStyle(Color.statusError)
                            .transition(.opacity)
                    }
                }

                Button(action: activate) {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.onPrimary)
                            .frame(width: 140, height: 24)
                    } else {
                        Text("Activate")
                            .font(.labelLG.weight(.semibold))
                            .foregroundStyle(Color.onPrimary)
                            .frame(width: 140, height: 24)
                    }
                }
                .padding(.vertical, Space.s2)
                .background(
                    Capsule()
                        .fill(Color.primaryFill)
                )
                .buttonStyle(.plain)
                .disabled(code.isEmpty || isActivating)
                .opacity((code.isEmpty || isActivating) ? 0.5 : 1)
                .keyboardShortcut(.defaultAction)
                .ctaShadow()

                Spacer()

                Text("This app is for authorized family members only.")
                    .font(.labelSM)
                    .foregroundStyle(Color.secondaryText)
                    .padding(.bottom, Space.s4)
            }
            .padding(Space.s10)
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func activate() {
        isActivating = true
        showError = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if KeychainService.activate(with: code) {
                withAnimation(.easeOut(duration: 0.2)) {
                    onActivated()
                }
            } else {
                showError = true
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
