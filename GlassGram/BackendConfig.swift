import Foundation

/// Backend configuration — the ONLY place a future server endpoint
/// will ever live. It is a fixed constant compiled into the app,
/// never user-editable: there is intentionally NO server/URL/host
/// field anywhere in the UI (standing user requirement — nobody
/// wants to type a server address). Signup stays exactly:
/// display name + invite code, nothing else.
///
/// v1 runs 100% locally and does not use this endpoint at all; the
/// constant is the single source of truth for the future backend
/// step, to be set once, in code, when that backend ships.
enum BackendConfig {
    static let endpoint = URL(string: "https://api.glassgram.app/v1")!
}
