import SwiftUI

/// Renders an illustration for a setup wizard step — either an SF Symbol or a bundled image.
struct StepIllustrationView: View {
    let illustration: StepIllustration?

    var body: some View {
        if let illustration {
            switch illustration.type {
            case .sfSymbol:
                Image(systemName: illustration.name)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, height: 120)

            case .bundledImage:
                Image(illustration.name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
