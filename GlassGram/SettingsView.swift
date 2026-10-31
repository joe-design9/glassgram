import SwiftUI

/// Tab 4 — Einstellungen: profile header + grouped glass cards with
/// colored icon tiles, modeled on the reference screenshots.
/// Functional rows: Gespeichertes, Letzte Anrufe, Mitteilungen
/// (toggles), Darstellung (font-size slider), name editing (saved
/// to the server profile), and — for admin accounts — the
/// server invite-code manager.
struct SettingsView: View {
    @EnvironmentObject private var store: Store

    private enum Route: Hashable {
        case notifications
        case privacy
        case storage
        case appearance
        case devices
        case folders
        case language
        case admin
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    profileCard
                    groupCard1
                    groupCard2
                    if BuildVariant.isAdmin && store.myProfile?.isAdmin == true {
                        adminCard
                    }
                    Text("GlassGram 2.0.0 — Chats laufen über den GlassGram-Server. Gespeichertes bleibt nur auf diesem iPhone.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(white: 0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .background { DepthBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
    }

    // MARK: Header + profile

    private var header: some View {
        Text("Einstellungen")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
    }

    private var profileCard: some View {
        VStack(spacing: 10) {
            AvatarView(title: store.profileName, colorIndex: 0, size: 84)
            Text(store.profileName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
            Text("@\(store.myProfile?.username ?? "glassgram") · online")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.secondaryText)
            EditNameButton()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassCard()
    }

    // MARK: Groups

    private var groupCard1: some View {
        VStack(spacing: 0) {
            Button {
                store.selectedTab = 0
                store.pendingChatID = Store.savedChatID
            } label: {
                SettingsRow(icon: "bookmark.fill", tile: .blue,
                            title: "Gespeichertes", chevron: true)
            }
            divider
            Button {
                store.selectedTab = 2
            } label: {
                SettingsRow(icon: "phone.fill", tile: .green,
                            title: "Letzte Anrufe", chevron: true)
            }
            divider
            NavigationLink(value: Route.devices) {
                SettingsRow(icon: "iphone", tile: .orange,
                            title: "Geräte", value: "1", chevron: true)
            }
            divider
            NavigationLink(value: Route.folders) {
                SettingsRow(icon: "folder.fill", tile: .cyan,
                            title: "Ordner", chevron: true)
            }
        }
        .glassCard()
    }

    private var groupCard2: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.notifications) {
                SettingsRow(icon: "bell.fill", tile: .red,
                            title: "Mitteilungen und Töne", chevron: true)
            }
            divider
            NavigationLink(value: Route.privacy) {
                SettingsRow(icon: "lock.fill", tile: .gray,
                            title: "Privatsphäre und Sicherheit", chevron: true)
            }
            divider
            NavigationLink(value: Route.storage) {
                SettingsRow(icon: "cylinder.fill", tile: .green,
                            title: "Daten und Speicher", chevron: true)
            }
            divider
            NavigationLink(value: Route.appearance) {
                SettingsRow(icon: "circle.lefthalf.filled", tile: .blue,
                            title: "Darstellung", chevron: true)
            }
            divider
            NavigationLink(value: Route.language) {
                SettingsRow(icon: "globe", tile: .indigo,
                            title: "Sprache", value: "Deutsch", chevron: true)
            }
        }
        .glassCard()
    }

    private var adminCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.admin) {
                SettingsRow(icon: "key.fill", tile: .orange,
                            title: "Admin · Invite-Codes",
                            value: "\(store.serverCodes.count)", chevron: true)
            }
        }
        .glassCard()
        .task {
            await store.refreshAdminCodes()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.6)
            .padding(.leading, 58)
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .notifications:
            SettingsDetailView(title: "Mitteilungen und Töne") {
                NotificationsSettings()
            }
        case .privacy:
            SettingsDetailView(title: "Privatsphäre und Sicherheit") {
                InfoLines(lines: [
                    "Dein Konto, deine Chats und deine Nachrichten liegen auf dem GlassGram-Server — nur so kannst du mit anderen schreiben.",
                    "„Gespeichertes“ ist die Ausnahme: Diese Nachrichten bleiben nur lokal auf diesem iPhone und verlassen das Gerät nie.",
                    "Invite-Codes steuern, wer sich registrieren darf — ohne Code kein Konto.",
                ])
            }
        case .storage:
            SettingsDetailView(title: "Daten und Speicher") {
                InfoLines(lines: [
                    "Nachrichten und Chats werden auf dem Server gespeichert und auf diesem Gerät zwischengespeichert, damit die App schnell startet.",
                    "Gespeichertes, Einstellungen und die Anrufliste liegen nur lokal auf dem Gerät.",
                ])
            }
        case .appearance:
            SettingsDetailView(title: "Darstellung") {
                AppearanceSettings()
            }
        case .devices:
            SettingsDetailView(title: "Geräte") {
                InfoLines(lines: [
                    "Dieses iPhone — aktiv, GlassGram 2.0.0.",
                    "Deine Sitzung bleibt sicher im Schlüsselbund dieses Geräts gespeichert.",
                ])
            }
        case .folders:
            SettingsDetailView(title: "Ordner") {
                InfoLines(lines: [
                    "Sobald Chats einem Ordner zugeordnet sind, erscheint der Ordner als Filter in der Chatliste.",
                ])
            }
        case .language:
            SettingsDetailView(title: "Sprache") {
                InfoLines(lines: [
                    "App-Sprache: Deutsch (fest in dieser Version).",
                ])
            }
        case .admin:
            AdminView()
        }
    }
}

// MARK: - Row building blocks

enum TileColor {
    case blue, green, orange, red, gray, cyan, indigo

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .green: return Color(red: 0.25, green: 0.72, blue: 0.35)
        case .orange: return Color(red: 0.95, green: 0.62, blue: 0.20)
        case .red: return Color(red: 0.93, green: 0.32, blue: 0.30)
        case .gray: return Color(white: 0.45)
        case .cyan: return Color(red: 0.25, green: 0.68, blue: 0.85)
        case .indigo: return Color(red: 0.42, green: 0.45, blue: 0.80)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let tile: TileColor
    let title: String
    var value: String? = nil
    var chevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(tile.color)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(title)
                .font(.system(size: 16.5))
                .foregroundStyle(.white)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.40))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail page scaffold

struct SettingsDetailView<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 38)
                }
                Spacer()
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 34, height: 38)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
        }
        .background { DepthBackdrop() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct InfoLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Color(white: 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Functional detail pages

struct NotificationsSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 0) {
            toggleRow(title: "Ton", isOn: binding(\.soundEnabled))
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.6).padding(.leading, 16)
            toggleRow(title: "Vibration beim Senden", isOn: binding(\.vibrationEnabled))
        }
        .glassCard()
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16.5))
                .foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.25, green: 0.72, blue: 0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func binding(_ keyPath: WritableKeyPath<GGSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0 }
        )
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                HStack {
                    Text("Design")
                        .font(.system(size: 16.5))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Schwarz")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Schriftgröße im Chat")
                        .font(.system(size: 16.5))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(store.settings.fontScale * 100)) %")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                Slider(value: fontScaleBinding, in: 0.85...1.3, step: 0.05)
                    .tint(Theme.accent)
                Text("Beispiel: So groß erscheint der Text in Chats.")
                    .font(.system(size: 16.5 * store.settings.fontScale))
                    .foregroundStyle(Color(white: 0.85))
            }
            .padding(16)
            .glassCard()
        }
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { store.settings.fontScale },
            set: { store.settings.fontScale = $0 }
        )
    }
}

// MARK: - Name editing

struct EditNameButton: View {
    @EnvironmentObject private var store: Store
    @State private var showSheet = false

    var body: some View {
        Button("Name bearbeiten") {
            showSheet = true
        }
        .font(.system(size: 15.5, weight: .medium))
        .foregroundStyle(Theme.accent)
        .sheet(isPresented: $showSheet) {
            EditNameSheet()
        }
    }
}

struct EditNameSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Anzeigename", text: $name)
                    .foregroundStyle(.white)
                    .font(.system(size: 17))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.clear, in: .rect(cornerRadius: 14))
                    .specularEdge(RoundedRectangle(cornerRadius: 14))
                Text("Der Name erscheint in deinem Profil und wird auf dem Server gespeichert, damit ihn deine Kontakte sehen.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .padding(20)
            .background { DepthBackdrop() }
            .navigationTitle("Name bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            Task { await store.updateDisplayName(trimmed) }
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(.black)
        .dismissKeyboardOnTap()
        .onAppear { name = store.profileName }
    }
}
