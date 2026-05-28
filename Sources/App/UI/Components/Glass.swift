import SwiftUI

enum Glass {
    static func fieldBackground() -> some ShapeStyle { .ultraThinMaterial }
}

struct GlassButton: ButtonStyle {
    var prominent: Bool = false
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                prominent
                    ? AnyShapeStyle(AppColors.accent.opacity(configuration.isPressed ? 0.75 : 0.95))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(prominent ? 0.10 : 0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassField: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Glass.fieldBackground())
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassField() -> some View {
        modifier(GlassField())
    }

    func glassButton(prominent: Bool = false) -> some View {
        buttonStyle(GlassButton(prominent: prominent))
    }
}

