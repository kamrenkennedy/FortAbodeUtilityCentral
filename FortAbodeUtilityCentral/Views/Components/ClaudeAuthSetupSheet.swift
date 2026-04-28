import SwiftUI
import AlignedDesignSystem

// MARK: - Claude Auth Setup Sheet (Phase 7)
//
// Two-step in-app OAuth setup. Replaces the old terminal dance
// (`claude setup-token` → `launchctl setenv CLAUDE_CODE_OAUTH_TOKEN ...`)
// which was brittle (resets on reboot, newline-in-token bugs, clipboard
// hijack failure modes when pasting commands).
//
// Step 1: open Terminal with `claude setup-token` so the user can mint a
// long-lived OAuth token. We can't avoid Terminal entirely because Anthropic
// only exposes token generation through the CLI.
//
// Step 2: user pastes the token into a SecureField here. We sanitize
// (strip whitespace + newlines), validate prefix, and store via
// ClaudeAuthKeychainService. The runner reads from Keychain at spawn —
// survives reboot, immune to clipboard hijack.

struct ClaudeAuthSetupSheet: View {

    let onConnected: () -> Void
    let onDismiss: () -> Void

    @State private var pastedToken: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        AlignedSheet(
            eyebrow: "Setup",
            title: "Connect your Claude account",
            badge: nil,
            idealWidth: 580,
            onDismiss: onDismiss,
            content: { contentBody },
            footer: { footerActions }
        )
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Fort Abode runs the Weekly Rhythm Engine through the Claude CLI. To authenticate without the engine 401-ing on every run, we store a long-lived OAuth token in your macOS Keychain.")
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s3) {
                stepHeader(number: "1", label: "Get a token from the Claude CLI")

                Text("Click the button below. A new Terminal window will open and run `claude setup-token`. Log in via your browser when prompted, then copy the token it prints. It starts with `sk-ant-oat01-`.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Terminal & run setup-token") {
                    runSetupTokenInTerminal()
                }
                .buttonStyle(.alignedSecondaryMini)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                stepHeader(number: "2", label: "Paste the token here")

                SecureField("sk-ant-oat01-…", text: $pastedToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onChange(of: pastedToken) { _, _ in
                        // Clear any prior validation error as soon as the user
                        // edits the field again.
                        errorMessage = nil
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.labelSM)
                        .foregroundStyle(Color.appError)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Newlines and whitespace are stripped automatically — terminal line-wrap won't break anything.")
                        .font(.labelSM)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stepHeader(number: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(number)
                .font(.labelMD.weight(.semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 16, alignment: .leading)
            Text(label)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Spacer()
            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.alignedSecondaryMini)

            Button("Connect") {
                attemptConnect()
            }
            .buttonStyle(.alignedPrimary)
            .disabled(!isPastedTokenPlausible)
        }
    }

    // MARK: - Actions

    private var isPastedTokenPlausible: Bool {
        // Cheap pre-validation that mirrors the keychain service's prefix
        // requirement, so the Connect button reflects what storeToken will
        // actually accept. Sanitize first so newlines don't trip the check.
        let cleaned = pastedToken.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map { String($0) }
            .joined()
        return cleaned.hasPrefix("sk-ant-oat01-") && cleaned.count > "sk-ant-oat01-".count
    }

    private func attemptConnect() {
        let stored = ClaudeAuthKeychainService.storeToken(pastedToken)
        if stored {
            errorMessage = nil
            pastedToken = ""
            onConnected()
        } else {
            errorMessage = "Token didn't validate. It should start with `sk-ant-oat01-` followed by characters. Re-run setup-token if you're not sure."
        }
    }

    private func runSetupTokenInTerminal() {
        // osascript spawn — opens a new Terminal window and runs the command.
        // We don't capture output; the user reads the printed token from
        // Terminal and copy-pastes into the SecureField above.
        let script = """
        tell application "Terminal"
            activate
            do script "claude setup-token"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
        } catch {
            errorMessage = "Couldn't launch Terminal automatically. Run `claude setup-token` yourself in any terminal, then paste the token below."
        }
    }
}
