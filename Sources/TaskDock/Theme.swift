import SwiftUI

/// Follows the system light/dark setting. Shared look: soft neutral canvas, white cards with a hairline border, grey filled fields, blue pills.
enum Theme {
    static let accent = Color(red: 0.17, green: 0.42, blue: 0.95)
    static let canvas = dynamic(NSColor(white: 0.965, alpha: 1), NSColor(white: 0.11, alpha: 1))
    static let card = dynamic(.white, NSColor(white: 0.165, alpha: 1))
    static let field = Color.primary.opacity(0.05)
    static let hover = Color.primary.opacity(0.06)
    static let selected = Color.primary.opacity(0.09)
    static let border = Color.primary.opacity(0.1)
    /// Placeholder and hint text (a step brighter than .secondary in dark mode).
    /// "Last time" notes: deep orange so it stays readable on white.
    static let note = dynamic(NSColor(red: 0.76, green: 0.35, blue: 0, alpha: 1), .systemOrange)
    static let muted = dynamic(NSColor(white: 0.45, alpha: 1), NSColor(white: 0.66, alpha: 1))
    /// Highlight for rows and tiles sitting on glass: a light frosted chip.
    static let onGlass = dynamic(NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0.1))
    static let strongBorder = Color.primary.opacity(0.18)

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }

    /// The pasted component's spring: cubic-bezier(0.175, 0.885, 0.32, 1.275).
    static let morph = Animation.timingCurve(0.175, 0.885, 0.32, 1.275, duration: 0.4)
    /// Content fading in inside the card: strong ease-out, no overshoot (the reference textarea uses ease-out).
    static let reveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
    /// Sections opening/closing inside a card: settles without overshoot, so nothing collides.
    static let settle = Animation.spring(duration: 0.35, bounce: 0)
    /// Strong ease-out for small, frequent feedback (hover, press, selection).
    static let quick = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
}

extension View {
    /// Frosted shell that holds the opaque "cloud" cards. A system material, not Liquid Glass:
    /// Liquid Glass flips light/dark to match what's behind it, which made panels open in the wrong theme.
    func glass(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(.regularMaterial, in: shape).overlay(shape.strokeBorder(Theme.border))
    }

    /// White rounded card with a hairline border and a faint shadow.
    func card(radius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

/// Content appearing inside a card: fades up out of a light blur.
struct BlurFade: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        content.opacity(hidden ? 0 : 1).blur(radius: hidden ? 4 : 0).offset(y: hidden ? 8 : 0)
    }
}

extension AnyTransition {
    static func reveal(reduceMotion: Bool) -> AnyTransition {
        // Leaving is a quick fade, so the old content never lingers while the card shrinks.
        .asymmetric(insertion: reduceMotion ? .opacity : .modifier(active: BlurFade(hidden: true), identity: BlurFade(hidden: false)),
                    removal: .opacity.animation(.easeOut(duration: 0.08)))
    }
}

/// Capsule button. Prominent = blue fill, otherwise a white pill with a hairline border.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.strongBorder))
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Full-width list row with a grey hover highlight, like a settings sidebar item.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(configuration.isPressed ? Theme.selected : hovering ? Theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Theme.quick, value: hovering)
        }
    }
}

/// Grey filled text field, like the reference's form inputs.
struct FilledFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
