import SwiftUI

@main
struct GlassGramApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Which of the two build variants this binary is.
/// Normal build: scheme "GlassGram" / configuration Release.
/// Admin build: scheme "GlassGramAdmin" / configuration ReleaseAdmin,
/// which sets the ADMIN_BUILD compilation condition.
enum BuildVariant {
    static var isAdmin: Bool {
        #if ADMIN_BUILD
        return true
        #else
        return false
        #endif
    }
}
