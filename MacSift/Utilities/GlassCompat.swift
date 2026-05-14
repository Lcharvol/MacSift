import SwiftUI

// macOS 26 Tahoe introduced Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`,
// `.buttonStyle(.glassProminent)`). The app is designed around that look, but we
// still want to run on macOS 15 (Sequoia) where those APIs do not exist. These
// thin compatibility wrappers apply the Tahoe APIs when available and fall back
// to ordinary materials / system button styles on older macOS.

extension View {
    @ViewBuilder
    func compatGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

enum CompatGlassButtonStyle {
    case regular
    case prominent
}

extension View {
    @ViewBuilder
    func compatGlassButtonStyle(_ style: CompatGlassButtonStyle = .regular) -> some View {
        if #available(macOS 26.0, *) {
            switch style {
            case .regular:
                self.buttonStyle(.glass)
            case .prominent:
                self.buttonStyle(.glassProminent)
            }
        } else {
            switch style {
            case .regular:
                self.buttonStyle(.bordered)
            case .prominent:
                self.buttonStyle(.borderedProminent)
            }
        }
    }
}
