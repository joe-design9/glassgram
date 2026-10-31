import SwiftUI

/// App root: the account phase decides what shows —
///   .checking          → splash while session + profile restore
///   .needsRegistration → RegistrationView
///   .needsCode         → CodeEntryView (normal build)
///   .waitingAdmin      → AdminWaitingView (admin build)
///   .ready             → the four tabs in a NATIVE TabView —
///                        iOS 26 renders its bar in the system's own
///                        Liquid Glass (the hand-built glass bar was
///                        rejected six times as a fake; the approved
///                        Muse app uses the native bar too).
struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Monochrome depth instead of flat black (v2.0.0):
            // every glass surface in the app refracts this.
            DepthBackdrop()
            switch store.accountPhase {
            case .checking:
                checkingView
            case .needsRegistration:
                RegistrationView()
            case .needsCode:
                CodeEntryView()
            case .waitingAdmin:
                AdminWaitingView()
            case .ready:
                mainTabs
            }
        }
        .task {
            await store.bootstrap()
        }
        .onAppear { store.startDemoDriverIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.appBecameActive() }
            }
        }
    }

    private var checkingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 92, height: 92)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(18))
            }
            .glassCircle(interactive: false)
            ProgressView()
                .tint(.white)
            Text("Verbinde …")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var mainTabs: some View {
        ZStack(alignment: .top) {
            TabView(selection: $store.selectedTab) {
                ChatsListView()
                    .tabItem { Label("Chats", systemImage: "message.fill") }
                    .tag(0)
                ContactsView()
                    .tabItem { Label("Kontakte", systemImage: "person.crop.circle.fill") }
                    .tag(1)
                CallsView()
                    .tabItem { Label("Anrufe", systemImage: "phone.fill") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
                    .tag(3)
                    .badge("\u{21}")
            }
            .tint(Theme.accent)
            .tabBarMinimizeBehavior(.never)

            statusBanner
        }
    }

    /// Connection state + transient messages, floating at the top:
    /// a persistent "Keine Verbindung zum Server" pill while the
    /// backend is unreachable, otherwise the auto-expiring banner.
    @ViewBuilder
    private var statusBanner: some View {
        if !store.connectionOnline {
            bannerPill(icon: "wifi.slash", text: "Keine Verbindung zum Server")
        } else if let text = store.bannerText {
            bannerPill(icon: "exclamationmark.circle.fill", text: text)
        }
    }

    private func bannerPill(icon: String, text: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassPill()
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 30)
        .allowsHitTesting(false)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: store.connectionOnline)
        .animation(.easeInOut(duration: 0.25), value: store.bannerText)
    }

}
