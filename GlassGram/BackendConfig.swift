import Foundation

/// Backend configuration — the ONLY place the server endpoint and
/// the public anon key live. Both are fixed constants compiled into
/// the app, never user-editable: there is intentionally NO
/// server/URL/host field anywhere in the UI (standing user
/// requirement — nobody wants to type a server address). Signup
/// stays exactly: display name + username + invite code, nothing
/// else.
///
/// The anon key is the project's PUBLIC client key — it is meant to
/// be embedded in the app. All data protection happens server-side
/// via Row Level Security on every table.
enum BackendConfig {
    /// Supabase project endpoint (fixed).
    static let endpoint = "https://limxytgpwbluhweykabe.supabase.co"

    /// Supabase anon (public) key.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxpbXh5dGdwd2JsdWh3ZXlrYWJlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMzOTU3NjgsImV4cCI6MjEwODk3MTc2OH0.-ce9Jk7VTkvrkmJTrEZPYSCzDrPNgs4uy9SCTRp5mmA"
}
