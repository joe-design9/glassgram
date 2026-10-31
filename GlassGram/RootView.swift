import SwiftUI

/// App root: the account phase decides what shows —
///   .checking          → splash while session + profile restore
///   .needsRegistration → RegistrationView
///   .needsCode         → CodeEntryView (normal build)
///   .waitingAdmin      → AdminWaitingView (admin build)
///   .ready             → the four tabs with the floating glass
///                        tab bar from the reference screenshots.
/// All four tab roots stay alive (opacity-switched) so navigation
/// state survives tab changes — same pattern as classic Telegram.
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
        ZStack(alignment: .bottom) {
            tabRoot(0) { ChatsListView() }
            tabRoot(1) { ContactsView() }
            tabRoot(2) { CallsView() }
            tabRoot(3) { SettingsView() }

            // Hide the tab bar while a conversation is open
            // (Telegram does the same — the input bar takes its place).
            if store.openChatID == nil {
                // A whisper of neutral light behind the floating bar,
                // so its glass visibly catches light over the black
                // (like Telegram's bar) instead of reading matte.
                tabBarSheen
                GlassTabBar(selected: $store.selectedTab)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            statusBanner
        }
        .animation(.easeInOut(duration: 0.22), value: store.openChatID)
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

    /// Extremely subtle monochrome radial sheen behind the tab bar
    /// (white ~5.5 %, fading to clear). Safe pattern: the size comes
    /// ONLY from the GeometryReader (the screen), the glow circle is
    /// positioned by its center and the whole layer is clipped to the
    /// screen — it can never inflate the layout. Non-interactive.
    private var tabBarSheen: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let diameter = size.width * 1.25
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.055), .clear],
                    center: .center, startRadius: 0, endRadius: diameter / 2
                ))
                .frame(width: diameter, height: diameter)
                .position(x: size.width / 2, y: size.height - 30)
        }
        .ignoresSafeArea()
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tabRoot<Content: View>(_ index: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(store.selectedTab == index ? 1 : 0)
            .allowsHitTesting(store.selectedTab == index)
            .accessibilityHidden(store.selectedTab != index)
    }
}

// MARK: - Floating glass tab bar

struct GlassTabBar: View {
    @Binding var selected: Int

    private struct Tab {
        let title: String
        let icon: String
        var badge: Bool = false
    }

    private let tabs: [Tab] = [
        Tab(title: "Chats", icon: "message.fill"),
        Tab(title: "Kontakte", icon: "person.crop.circle.fill"),
        Tab(title: "Anrufe", icon: "phone.fill"),
        Tab(title: "Einstellungen", icon: "gearshape.fill", badge: true),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs.indices, id: \.self) { index in
                let tab = tabs[index]
                Button {
                    selected = index
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 21))
                            if tab.badge {
                                Circle()
                                    .fill(Theme.badgeRed)
                                    .frame(width: 11, height: 11)
                                    .overlay(
                                        Text("!")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                    .offset(x: 5, y: -3)
                            }
                        }
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected == index ? Theme.accent : Color(white: 0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected == index {
                            // Glass-on-glass selection (v2.0.2) —
                            // the flat white-0.18 milk fill is gone.
                            Capsule()
                                .glassEffect(.regular.tint(Theme.accent.opacity(0.30)),
                                             in: .capsule)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        // The bar FLOATS over the scrolling lists (they pass
        // beneath it in the ZStack) and uses the INTERACTIVE
        // glass variant, so it refracts content and answers
        // touches with Apple's specular bounce (v2.0.0).
        .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: .capsule)
        .specularEdge(Capsule())
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 7)
    }
}
