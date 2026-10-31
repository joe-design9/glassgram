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

// MARK: - Glass styles
//
// Since 1.1.0 the glass is deliberately BRIGHTER: on a pure-black
// canvas the old tints (0.055–0.07 white) read as flat matte gray.
// Every glass surface now gets three layers:
//   1. .glassEffect with a noticeably lighter neutral tint,
//   2. a specular edge — a 1 pt gradient stroke, bright at the top
//      edge and fading downward, like light catching real glass,
//   3. a soft drop shadow so the chrome floats over the black.

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
        glassEffect(.regular.tint(.white.opacity(0.13)),
                    in: .rect(cornerRadius: cornerRadius))
            .specularEdge(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Capsule glass — pills, segmented controls, the input bar,
    /// the floating tab bar.
    func glassPill(interactive: Bool = false) -> some View {
        glassEffect(interactive
                        ? .regular.tint(.white.opacity(0.14)).interactive()
                        : .regular.tint(.white.opacity(0.14)),
                    in: .capsule)
            .specularEdge(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    /// Round glass button (header actions, call controls).
    func glassCircle(interactive: Bool = true) -> some View {
        glassEffect(interactive
                        ? .regular.tint(.white.opacity(0.14)).interactive()
                        : .regular.tint(.white.opacity(0.14)),
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
