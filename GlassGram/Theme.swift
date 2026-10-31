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

    /// Neutral smoky glass tint - copied 1:1 from the approved
    /// Muse app (Palette.glassTint, dark variant). In that app
    /// EVERY neutral glass surface carries this tint; GlassGram's
    /// panels had NO tint at all, and untinted .regular over a
    /// dark backdrop renders as thin dark plastic - the last real
    /// code difference behind the repeated "Fake Glass" verdicts.
    /// Never ship an untinted neutral glass surface again.
    static let glassTint = Color(uiColor: UIColor(white: 0.08, alpha: 0.52))

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

// MARK: - Depth backdrop (v2.0.2 — a wallpaper, not empty black)
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
// v2.0.1 therefore shipped a proper dark wallpaper — but its
// light fields were still too dim: behind the gate screens the
// glass card read as frosted gray (the user's fourth rejection).
// v2.0.2 strengthens every field (accent 0.20→0.34, teal
// 0.13→0.20) and adds a third, indigo field at mid-right, so
// every screen — registration included — has unmistakable
// color and tonal variation for the glass to refract, while
// the identity stays deep blue-black.
struct DepthBackdrop: View {
    var body: some View {
        ZStack {
            // Deep blue-black base (v2.0.2: lifted top stop).
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.085, blue: 0.190),
                    Color(red: 0.012, green: 0.016, blue: 0.035),
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Accent light field from the upper left — the main
            // thing the floating header/tab glass refracts.
            RadialGradient(
                colors: [Theme.accent.opacity(0.34), .clear],
                center: UnitPoint(x: 0.12, y: 0.02),
                startRadius: 0, endRadius: 620
            )
            // Indigo depth at mid-right (v2.0.2) — gives the
            // right-hand glass edges their own color to bend.
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.30, blue: 0.85).opacity(0.15), .clear],
                center: UnitPoint(x: 0.92, y: 0.30),
                startRadius: 0, endRadius: 480
            )
            // Cool teal depth from the lower right.
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.45, blue: 0.50).opacity(0.20), .clear],
                center: UnitPoint(x: 0.95, y: 0.88),
                startRadius: 0, endRadius: 560
            )
            // A soft neutral lift behind the tab bar zone.
            RadialGradient(
                colors: [Color(white: 0.13), .clear],
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
// v2.0.2 fix — the .clear mistake, corrected. v2.0.1 switched
// every surface from .regular to .clear on a wrong theory
// ("real glass is clear"). Wrong: .clear is Apple's variant
// for media backgrounds and renders as a faint tinted film
// over dark/flat content — the "Fake Glass" the user rejected
// five times. The two apps the user APPROVED (Muse Royal
// Casino, the Muse app) both use .regular everywhere.
// GlassGram now uses .regular everywhere too — same variant,
// same tints, regardless of what sits behind the surface.
// NEVER switch this back to .clear.

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
        glassEffect(.regular.tint(Theme.glassTint), in: .rect(cornerRadius: cornerRadius))
            .specularEdge(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Capsule glass — pills, segmented controls, the input bar,
    /// the floating tab bar.
    func glassPill(interactive: Bool = false) -> some View {
        glassEffect(interactive ? .regular.tint(Theme.glassTint).interactive() : .regular.tint(Theme.glassTint),
                    in: .capsule)
            .specularEdge(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Round glass button (header actions, call controls).
    func glassCircle(interactive: Bool = true) -> some View {
        glassEffect(interactive ? .regular.tint(Theme.glassTint).interactive() : .regular.tint(Theme.glassTint),
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
