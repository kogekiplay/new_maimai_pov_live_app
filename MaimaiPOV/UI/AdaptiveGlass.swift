import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassPanel(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                if let tint {
                    self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                }
            } else {
                if let tint {
                    self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                } else {
                    self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func adaptiveGlassPanelBackground(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.background {
                if let tint {
                    Color.clear
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                } else {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                }
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func adaptiveGlassGroup(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }
}
