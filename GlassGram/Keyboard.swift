import SwiftUI
import UIKit

// MARK: - Tap-outside keyboard dismissal
//
// GlassGram rule (carried over from the sister project): the keyboard must go away by TAPPING anywhere
// outside a text field ("wegdrücken") — not via a toolbar button.
//
// Implementation: ONE layer only — a window-level
// UITapGestureRecognizer (`KeyboardTapGuard`) that observes every tap
// WITHOUT cancelling touches (buttons, scrolling and lists keep
// working: `cancelsTouchesInView = false` and simultaneous
// recognition). Taps landing on a text input are excluded in
// `shouldReceive` — those taps are meant to focus the field — and
// every other tap resigns the first responder.
//
// HISTORY (v1.1.0 bug fix): there used to be a second layer — a
// SwiftUI `simultaneousGesture(TapGesture())` on each screen root.
// That gesture sat on the containers wrapping the chat/contact
// LISTS and swallowed row taps: on v1.0.0 the chat rows stopped
// responding ("Ich kann auf die Chats nicht draufdrücken"). A
// SwiftUI tap gesture must never overlay a List — the UIKit guard
// below does the whole job safely on its own.
// `.scrollDismissesKeyboard(.interactively)` stays on scroll views.

enum KeyboardDismisser {
    /// Resigns whatever is currently first responder (field/search bar).
    static func hide() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

/// Window-level tap observer: dismisses the keyboard on any tap that
/// does not land on a text input.
final class KeyboardTapGuard: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardTapGuard()

    private weak var installedWindow: UIWindow?

    /// When the most recent tap landed on a text input (kept for
    /// diagnostics; the recognizer itself excludes those taps in
    /// `shouldReceive`).
    private(set) var lastInputTouchAt: Date = .distantPast

    /// When the most recent tap landed on a control (button etc.).
    /// Control taps are ACTIONS — most importantly the chat's send
    /// button — never dismiss taps. Bug found 2026-10-31 (same flaw
    /// as in the sister app): the guard used to resign the first
    /// responder on EVERY non-input tap, so each tap on "send"
    /// killed the keyboard and it had to be reopened per message.
    private(set) var lastControlTouchAt: Date = .distantPast

    /// Installs the recognizer on the current key window (idempotent —
    /// a new window, e.g. after scene changes, gets its own recognizer).
    func installIfNeeded() {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let keyWindow, installedWindow !== keyWindow else { return }
        installedWindow = keyWindow

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false // never steal touches from controls
        tap.delegate = self
        keyWindow.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        // Belt and braces: never resign right after an input or
        // control touch (the delegate normally filters those out
        // before recognition already).
        let now = Date()
        if now.timeIntervalSince(lastInputTouchAt) < 0.4
            || now.timeIntervalSince(lastControlTouchAt) < 0.4 {
            return
        }
        KeyboardDismisser.hide()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Taps on (or inside) a text input focus that input — never
        // treat them as dismiss taps. Remember the moment so the
        // SwiftUI gesture layer can apply the same guard.
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                lastInputTouchAt = Date()
                return false
            }
            if current is UIControl {
                // Buttons and other controls perform an action with
                // the tap (send, call, tab …) — the keyboard must
                // survive it. Dismissal is only for taps on dead
                // surface: message background, empty areas.
                lastControlTouchAt = Date()
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true // observe alongside scroll/button recognizers, never block them
    }
}

/// Zero-size, non-interactive marker view whose appearance (re)installs
/// the window tap guard. Used as the background of every screen root.
private struct KeyboardInstallView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { KeyboardTapGuard.shared.installIfNeeded() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { KeyboardTapGuard.shared.installIfNeeded() }
    }
}

/// Tap-outside-to-dismiss, applied to a screen's root container.
/// ONLY installs the UIKit window guard (as a background marker) —
/// deliberately NO SwiftUI gesture on the content: a TapGesture over
/// a List swallows the rows' taps (the v1.0.0 chat-tap bug).
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardInstallView())
    }
}

extension View {
    /// Dismisses the keyboard when the user taps anywhere outside a
    /// text field. Apply once on each screen/sheet root.
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}
