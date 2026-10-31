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

// MARK: - Depth backdrop
//
// Pure black plus ONE neutral sheen - the exact backdrop recipe
// of the approved Muse app (AppBackdrop: paper black, a white
// 0.075 radial at the top). This replaces the navy wallpaper
// (v2.0.0-v2.0.2): its blue cast pushed into every glass surface
// and read as dark plastic. The colorful refraction the old
// comment chased belongs to CONTENT (avatars, bubbles, photos),
// not to a colored scene wash.
struct DepthBackdrop: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.white.opacity(0.075), Color.white.opacity(0.0)],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 0,
                endRadius: 620
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
    /// The approved Muse app's exact rim values: white 0.30 at the
    /// top edge fading to white 0.04 at the bottom, 1 pt. The hotter
    /// 0.55 rim this replaces drew a hard plastic edge on dark
    /// panels. Never hit-testable.
    func specularEdge<S: InsettableShape>(_ shape: S) -> some View {
        overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.04)],
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
