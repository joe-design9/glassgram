import SwiftUI
import UIKit

/// GlassGram design tokens: pure black canvas, REAL Liquid Glass
/// (.glassEffect) everywhere — never a material fallback — and the
/// Telegram blue as the single accent.
enum Theme {
    /// Telegram blue.
    static let accent = Color(red: 0.165, green: 0.671, blue: 0.933) // #2AABEE
    static let background = Color.black
    static let secondaryText = Color(white: 0.62)
    static let badgeRed = Color(red: 0.93, green: 0.30, blue: 0.28)

    /// Muted avatar colors (deliberately no pink-heavy palette).
    static let avatarColors: [Color] = [
        Color(red: 0.30, green: 0.55, blue: 0.85), // blue
        Color(red: 0.45, green: 0.52, blue: 0.60), // slate
        Color(red: 0.35, green: 0.65, blue: 0.45), // green
        Color(red: 0.85, green: 0.58, blue: 0.25), // orange
        Color(red: 0.25, green: 0.62, blue: 0.68), // teal
        Color(red: 0.55, green: 0.58, blue: 0.65), // gray
        Color(red: 0.40, green: 0.48, blue: 0.75), // muted indigo
        Color(red: 0.60, green: 0.50, blue: 0.38), // brown
    ]
}

// MARK: - Depth backdrop (v2.0.1 — a wallpaper, not empty black)
//
// Three rejected builds taught the same lesson: Liquid Glass is
// refraction of whatever sits BEHIND the surface. v1.x floated
// tinted .regular glass over pure black — nothing to refract, so
// it read as matte gray plastic (the user's verdict, three times:
// "immer noch kein Liquid Glass"). v2.0.0 added faint monochrome
// depth (whites at 0.05–0.075) — on a real device still basically
// black, still nothing to bend. Telegram's dark mode has the
// answer: a dark WALLPAPER with real tonal and color variation,
// so its glass always has something to refract — even in an
// empty app.
//
// v2.0.1 therefore ships a proper dark wallpaper: a deep
// blue-black base gradient plus two large, soft light fields
// (accent-blue from the top, a cool teal whisper from the lower
// right). Still unmistakably "black" as an identity, but every
// glass surface — tab bar, pills, bubbles — now bends visible
// light and color, in empty and full screens alike.
struct DepthBackdrop: View {
    var body: some View {
        ZStack {
            // Deep blue-black base (top #0A0F1E → bottom #04050A).
            LinearGradient(
                colors: [
                    Color(red: 0.039, green: 0.059, blue: 0.118),
                    Color(red: 0.016, green: 0.020, blue: 0.039),
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Accent light field from the upper left — the main
            // thing the floating header/tab glass refracts.
            RadialGradient(
                colors: [Theme.accent.opacity(0.20), .clear],
                center: UnitPoint(x: 0.12, y: 0.02),
                startRadius: 0, endRadius: 560
            )
            // Cool teal depth from the lower right.
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.45, blue: 0.50).opacity(0.13), .clear],
                center: UnitPoint(x: 0.95, y: 0.88),
                startRadius: 0, endRadius: 520
            )
            // A soft neutral lift behind the tab bar zone.
            RadialGradient(
                colors: [Color(white: 0.10), .clear],
                center: .bottom, startRadius: 0, endRadius: 380
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Glass styles
//
// v2.0.1 — the .clear reckoning. Every neutral surface used
// .regular (the FROSTED variant) plus a white tint at 0.13–0.14:
// two milky layers that read as gray plastic. Real Liquid Glass —
// Apple's demos, Telegram's bars — is the CLEAR variant: nearly
// transparent, strong refraction and edge lensing, no milk film.
// All neutral glass is therefore .clear with NO tint; color lives
// only in the wallpaper behind it and in the accent-tinted own
// bubbles / CTA buttons. The specular stroke and float shadow
// stay on top.

extension View {
    /// Specular top highlight: gradient stroke over a glass shape.
    /// Bright (.white 0.55) at the top edge, fading to clear at the
    /// bottom. Never hit-testable.
    func specularEdge<S: InsettableShape>(_ shape: S) -> some View {
        overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55),
                             .white.opacity(0.14),
                             .white.opacity(0.03),
                             .clear],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        )
    }

    /// Grouped card (Settings-style): one glass surface around content.
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            .specularEdge(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Capsule glass — pills, segmented controls, the input bar,
    /// the floating tab bar.
    func glassPill(interactive: Bool = false) -> some View {
        glassEffect(interactive ? .clear.interactive() : .clear,
                    in: .capsule)
            .specularEdge(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Round glass button (header actions, call controls).
    func glassCircle(interactive: Bool = true) -> some View {
        glassEffect(interactive ? .clear.interactive() : .clear,
                    in: .circle)
            .specularEdge(Circle())
            .shadow(color: .black.opacity(0.40), radius: 9, x: 0, y: 4)
    }
}

// MARK: - Avatar

struct AvatarView: View {
    let title: String
    let colorIndex: Int
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(Theme.avatarColors[colorIndex % Theme.avatarColors.count])
            .frame(width: size, height: size)
            .overlay(
                Text(avatarInitials(title))
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// The blue bookmark avatar of the "Gespeichertes" chat.
struct SavedAvatarView: View {
    var size: CGFloat = 52

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "bookmark.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
