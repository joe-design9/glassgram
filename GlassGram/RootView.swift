import SwiftUI

/// App root: invite gate first, then the four tabs with the floating
/// glass tab bar from the reference screenshots. All four tab roots
/// stay alive (opacity-switched) so navigation state survives tab
/// changes — same pattern as classic Telegram.
struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.gatePassed {
                mainTabs
            } else {
                WelcomeGateView()
            }
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
                GlassTabBar(selected: $store.selectedTab)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.openChatID)
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
                            Capsule().fill(.white.opacity(0.13))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .capsule)
    }
}

// MARK: - Welcome / invite gate

/// First-launch gate (both builds): display name + invite code.
/// Valid code → the gate opens permanently. Validation is fully
/// offline via the shared algorithm in InviteCode.swift.
struct WelcomeGateView: View {
    @EnvironmentObject private var store: Store
    @State private var name: String = ""
    @State private var code: String = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)

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

                VStack(spacing: 8) {
                    Text("Willkommen bei GlassGram")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Der Messenger im Liquid-Glass-Design.\nAlles bleibt lokal auf diesem iPhone.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    field(icon: "person.fill", placeholder: "Anzeigename", text: $name)
                    field(icon: "key.fill", placeholder: "Einladungscode · GG-______-______", text: $code, codeStyle: true)

                    if let error {
                        Text(error)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.badgeRed)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        if store.passGate(name: name, code: code) {
                            error = nil
                        } else {
                            error = "Dieser Code ist ungültig. Prüfe die Schreibweise — der Code hat die Form GG-XXXXXX-XXXXXX."
                        }
                    } label: {
                        Text("Los geht's")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.75)).interactive(), in: .capsule)
                }
                .padding(20)
                .glassCard()

                if BuildVariant.isAdmin {
                    Text("Admin-Build: Neue Codes erstellst du später in den Einstellungen unter „Admin“.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Text("Kein Konto, kein Server — der Code wird nur auf dem Gerät geprüft.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .onAppear {
            if name.isEmpty { name = store.profileName }
        }
    }

    private func field(icon: String, placeholder: String,
                       text: Binding<String>, codeStyle: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
                .font(.system(size: 16, design: codeStyle ? .monospaced : .default))
                .textInputAutocapitalization(codeStyle ? .characters : .words)
                .autocorrectionDisabled(codeStyle)
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
