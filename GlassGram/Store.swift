import Foundation

/// Central app state.
///
/// Since v2.0.0 GlassGram is a real client for the fixed Supabase
/// backend (see BackendConfig / SupabaseClient):
///   - the account (anonymous auth + profiles row) lives server-side,
///   - 1:1 chats, contacts (username search) and invite codes are
///     server-backed and kept fresh by polling,
///   - "Gespeichertes" (saved messages), the app settings and the
///     (local) call log never leave the device.
@MainActor
final class Store: ObservableObject {
    static let savedChatID = "saved"

    /// Chat ids of server conversations are "srv-<partner profile id>".
    static let serverChatPrefix = "srv-"

    /// QA screenshot mode (v2.0.0, see QA.md): true ONLY in the QA
    /// build configuration (compilation condition QA — a clone of
    /// Debug) AND when the process was launched with `-UITestMode`.
    /// Release/ReleaseAdmin never compile the QA condition, so the
    /// sample data below is unreachable in shipped builds even if
    /// someone passes the argument.
    static var isUITestMode: Bool {
        #if QA
        return ProcessInfo.processInfo.arguments.contains("-UITestMode")
        #else
        return false
        #endif
    }

    private enum Keys {
        static let profileName = "gg.profileName"
        // v2 key set (since 1.1.0): the app starts EMPTY like a real
        // messenger — the v1 keys held demo seed content and are
        // deliberately abandoned so an upgrade starts clean.
        static let localMessages = "gg.messages.v2"
        static let settings = "gg.settings.v2"
        static let initialized = "gg.initialized.v2"
        // v2.0.0 server-state caches (device-local mirrors).
        static let myProfile = "gg.myProfile.v1"
        static let partners = "gg.partners.v1"
        static let serverMessages = "gg.serverMessages.v1"
        static let lastRead = "gg.lastRead.v1"
        static let forgotten = "gg.forgotten.v1"
        static let calls = "gg.calls.v2"
    }

    // MARK: - Account state

    /// Registration / routing state machine, driven by the server
    /// profile's flags (activated / is_admin).
    enum AccountPhase {
        case checking          // restoring session + profile
        case needsRegistration // no usable account yet → form
        case needsCode         // profile exists, not activated (normal build)
        case waitingAdmin      // profile exists, not activated (admin build)
        case ready             // activated → the four tabs
    }

    @Published var accountPhase: AccountPhase = .checking
    @Published var myProfile: GGProfile?
    /// False after a backend call failed with a connectivity error.
    @Published var connectionOnline: Bool = true
    /// Transient banner text (send failures, code errors …).
    @Published var bannerText: String?

    private let client = SupabaseClient.shared
    private var bannerTask: Task<Void, Never>?
    private var listPollTask: Task<Void, Never>?
    private var chatPollTask: Task<Void, Never>?

    // MARK: - Published state

    /// Display name shown in the settings header (mirrors the
    /// server profile once registered).
    @Published var profileName: String = "Joel" {
        didSet { UserDefaults.standard.set(profileName, forKey: Keys.profileName) }
    }

    /// The unified chat list (Gespeichertes + one entry per server
    /// partner). Rebuilt from `partners` — never persisted itself.
    @Published var chats: [GGChat] = []

    /// Contact rows derived from `partners` (kept for the views
    /// that list contacts: Kontakte tab, pickers, call rows).
    @Published var contacts: [GGContact] = []

    /// Chat partners I have a conversation with (server profiles),
    /// persisted so the list renders before the first poll lands.
    @Published var partners: [GGProfile] = []

    /// LOCAL messages — in v2.0 this only ever holds the
    /// "Gespeichertes" conversation. Never leaves the device.
    @Published var messages: [String: [GGMessage]] = [:] {
        didSet { persist(messages, key: Keys.localMessages) }
    }

    /// Server messages per chat id (device cache of the server
    /// truth, persisted for instant/offline rendering).
    @Published var serverMessages: [String: [GGMessage]] = [:] {
        didSet { persist(serverMessages, key: Keys.serverMessages) }
    }

    /// Optimistic outgoing messages not yet confirmed by a poll.
    private var pendingMessages: [String: [GGMessage]] = [:]

    /// Per-partner "read up to" timestamps (unread derivation).
    private var lastRead: [String: Date] = [:] {
        didSet { persistCodable(lastRead.mapValues { $0.timeIntervalSince1970 }, key: Keys.lastRead) }
    }

    /// Partners the user deleted from the list: profile id → the
    /// moment of deletion. They reappear only if a NEWER message
    /// arrives from them.
    private var forgottenPartners: [String: Date] = [:] {
        didSet { persistCodable(forgottenPartners.mapValues { $0.timeIntervalSince1970 }, key: Keys.forgotten) }
    }

    /// Local call log (Anrufe tab stays local — no server calls).
    @Published var calls: [GGCall] = [] {
        didSet { persist(calls, key: Keys.calls) }
    }

    @Published var settings: GGSettings = GGSettings() {
        didSet { persist(settings, key: Keys.settings) }
    }

    // MARK: Kontakte search + Admin

    @Published var searchResults: [GGProfile] = []
    @Published var isSearching: Bool = false

    /// Server-side invite codes (admin build + is_admin profile).
    @Published var serverCodes: [GGInviteCodeRow] = []
    /// Display names for codes' used_by ids.
    @Published var codeUsedByNames: [String: String] = [:]
    @Published var adminBusy: Bool = false

    /// The chat currently on screen, if any (drives unread + tab bar).
    @Published var openChatID: String?

    /// Set by other tabs ("open this chat") — ChatsListView consumes it.
    @Published var pendingChatID: String?

    /// Selected main tab (RootView binds to this so tabs can jump).
    @Published var selectedTab: Int = 0

    // MARK: Init

    init() {
        let defaults = UserDefaults.standard
        profileName = defaults.string(forKey: Keys.profileName) ?? "Joel"

        if defaults.bool(forKey: Keys.initialized) {
            messages = load(Keys.localMessages) ?? [:]
            calls = load(Keys.calls) ?? []
            if let storedSettings: GGSettings = load(Keys.settings) {
                settings = storedSettings
            }
        } else {
            // First launch ever: empty local state. (didSet does
            // not fire during init — persist explicitly.)
            messages = [:]
            calls = []
            persist(messages, key: Keys.localMessages)
            persist(calls, key: Keys.calls)
            persist(settings, key: Keys.settings)
            defaults.set(true, forKey: Keys.initialized)
        }

        serverMessages = load(Keys.serverMessages) ?? [:]
        partners = load(Keys.partners) ?? []
        if let storedProfile: GGProfile = load(Keys.myProfile) {
            myProfile = storedProfile
        }
        let storedRead: [String: Double] = load(Keys.lastRead) ?? [:]
        lastRead = storedRead.mapValues { Date(timeIntervalSince1970: $0) }
        let storedForgotten: [String: Double] = load(Keys.forgotten) ?? [:]
        forgottenPartners = storedForgotten.mapValues { Date(timeIntervalSince1970: $0) }

        rebuildChats()

        if Store.isUITestMode {
            seedQASampleData()
        }
    }

    // MARK: - QA screenshot mode

    /// Populates the app with purely LOCAL sample content so the
    /// parent can screenshot the real glass surfaces (floating tab
    /// bar, headers, bubbles) over scrolling content in the
    /// Simulator — see QA.md. Only ever called under
    /// `Store.isUITestMode`; registration/auth never run in this
    /// mode (bootstrap no-ops because the phase starts at .ready)
    /// and every network entry point below is QA-guarded.
    private func seedQASampleData() {
        let now = Date()
        func minutesAgo(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        func msg(_ chatID: String, _ mine: Bool, _ text: String, _ date: Date) -> GGMessage {
            GGMessage(chatID: chatID, isMine: mine, text: text, date: date)
        }

        let me = GGProfile(id: "00000000-0000-0000-0000-000000000001",
                           username: "qa", displayName: "QA Tester",
                           isAdmin: false, activated: true)
        myProfile = me
        profileName = me.displayName

        let samplePartners: [GGProfile] = [
            GGProfile(id: "11111111-1111-1111-1111-111111111111",
                      username: "lena.m", displayName: "Lena Meyer",
                      isAdmin: false, activated: true),
            GGProfile(id: "22222222-2222-2222-2222-222222222222",
                      username: "max_b", displayName: "Max Berger",
                      isAdmin: false, activated: true),
            GGProfile(id: "33333333-3333-3333-3333-333333333333",
                      username: "sophie", displayName: "Sophie Klein",
                      isAdmin: false, activated: true),
            GGProfile(id: "44444444-4444-4444-4444-444444444444",
                      username: "team.kanal", displayName: "Team Kanal",
                      isAdmin: false, activated: true),
            GGProfile(id: "55555555-5555-5555-5555-555555555555",
                      username: "jonas.w", displayName: "Jonas Weber",
                      isAdmin: false, activated: true),
            GGProfile(id: "66666666-6666-6666-6666-666666666666",
                      username: "emma.s", displayName: "Emma Schneider",
                      isAdmin: false, activated: true),
            GGProfile(id: "77777777-7777-7777-7777-777777777777",
                      username: "lukas.f", displayName: "Lukas Fischer",
                      isAdmin: false, activated: true),
            GGProfile(id: "88888888-8888-8888-8888-888888888888",
                      username: "mia.h", displayName: "Mia Hoffmann",
                      isAdmin: false, activated: true),
            GGProfile(id: "99999999-9999-9999-9999-999999999999",
                      username: "paul.w", displayName: "Paul Wagner",
                      isAdmin: false, activated: true),
        ]
        partners = samplePartners

        var server: [String: [GGMessage]] = [:]
        let lena = Store.chatID(forPartner: samplePartners[0].id)
        server[lena] = [
            msg(lena, false, "Morgen! Endlich Wochenende in Sicht", minutesAgo(180)),
            msg(lena, true, "Ja! Noch der Termin gleich, dann ist Ruhe", minutesAgo(178)),
            msg(lena, false, "Ich hab gestern den Zug nach Hause fast verpasst", minutesAgo(150)),
            msg(lena, true, "Wieder am Handy gewesen, oder? 😄", minutesAgo(148)),
            msg(lena, false, "Vielleicht. Nur ein bisschen. Okay, komplett.", minutesAgo(146)),
            msg(lena, true, "Klassiker. Erzähl weiter", minutesAgo(144)),
            msg(lena, false, "Hey! Hast du die Fotos von gestern gesehen?", minutesAgo(64)),
            msg(lena, true, "Ja, die sind richtig gut geworden", minutesAgo(62)),
            msg(lena, false, "Das dritte ist mein Favorit, das Licht war perfekt", minutesAgo(61)),
            msg(lena, true, "Stimmt! Schick ich dir gleich in groß", minutesAgo(60)),
            msg(lena, false, "Und, bist du morgen dabei?", minutesAgo(31)),
            msg(lena, true, "Klar, ich bring den Kuchen mit", minutesAgo(29)),
            msg(lena, false, "Perfekt. Treffen ist um 10 am Eingang", minutesAgo(14)),
            msg(lena, false, "Wir sehen uns morgen um 10, oder?", minutesAgo(12)),
        ]
        let maxChat = Store.chatID(forPartner: samplePartners[1].id)
        server[maxChat] = [
            msg(maxChat, true, "Hast du den Build von gestern getestet?", hoursAgo(26)),
            msg(maxChat, false, "Läuft. Nur der eine Button klemmt noch", hoursAgo(25)),
            msg(maxChat, true, "Okay, schau ich mir heute Abend an", hoursAgo(25)),
        ]
        let sophie = Store.chatID(forPartner: samplePartners[2].id)
        server[sophie] = [
            msg(sophie, false, "Danke für die Hilfe beim Umzug!", hoursAgo(49)),
            msg(sophie, true, "Jederzeit wieder", hoursAgo(48)),
        ]
        let team = Store.chatID(forPartner: samplePartners[3].id)
        server[team] = [
            msg(team, false, "Release-Notes sind im Kanal gepinnt", hoursAgo(74)),
        ]
        let jonas = Store.chatID(forPartner: samplePartners[4].id)
        server[jonas] = [
            msg(jonas, true, "Spiel am Sonntag steht?", hoursAgo(96)),
            msg(jonas, false, "Steht. Ich bring die Trikots mit", hoursAgo(95)),
        ]
        // Extra partners so the QA chat list is long enough for
        // rows to slide beneath the floating glass tab bar in
        // the screenshots — the refraction proof.
        let emma = Store.chatID(forPartner: samplePartners[5].id)
        server[emma] = [
            msg(emma, false, "Der Termin steht jetzt fest", hoursAgo(120)),
        ]
        let lukas = Store.chatID(forPartner: samplePartners[6].id)
        server[lukas] = [
            msg(lukas, true, "Datei ist im Ordner abgelegt", hoursAgo(140)),
        ]
        let mia = Store.chatID(forPartner: samplePartners[7].id)
        server[mia] = [
            msg(mia, false, "Danke, das hat super geklappt!", hoursAgo(170)),
        ]
        let paul = Store.chatID(forPartner: samplePartners[8].id)
        server[paul] = [
            msg(paul, false, "Wir telefonieren morgen früh", hoursAgo(200)),
        ]
        serverMessages = server

        messages = [Store.savedChatID: [
            msg(Store.savedChatID, true, "Idee: Geburtstagsgeschenk für Lena", hoursAgo(5)),
            msg(Store.savedChatID, true, "Screenshot-Checkliste für v2.0.0", hoursAgo(3)),
        ]]

        calls = [
            GGCall(contactID: samplePartners[1].id, date: hoursAgo(26),
                   direction: .outgoing, missed: false, durationSec: 184),
        ]

        // Lena's chat carries an unread badge for the screenshots.
        rebuildChats(unreadByChat: [lena: 1])
        accountPhase = .ready

        // QA screenshot targeting: `-UITestScreen chat|contacts`
        // picks the start screen so simctl can capture each surface
        // without taps. QA mode only (this function never runs in
        // release builds).
        let qaArgs = ProcessInfo.processInfo.arguments
        if let idx = qaArgs.firstIndex(of: "-UITestScreen"), idx + 1 < qaArgs.count {
            switch qaArgs[idx + 1] {
            case "contacts":
                selectedTab = 1
            case "chat":
                selectedTab = 0
                pendingChatID = lena
            default:
                break
            }
        }
    }

    // MARK: - Bootstrap / routing

    /// Called once at launch (RootView.task): restore the session,
    /// fetch the profile, route by its flags.
    func bootstrap() async {
        guard accountPhase == .checking else { return }
        guard await client.hasSession else {
            accountPhase = .needsRegistration
            return
        }
        do {
            if let profile = try await client.fetchOwnProfile() {
                connectionOnline = true
                adoptProfile(profile)
                route(for: profile)
                if accountPhase == .ready {
                    startPolling()
                    await refreshInbox()
                }
            } else if myProfile != nil {
                // Session exists but the profile row is gone —
                // cannot happen in the normal flow; re-register.
                accountPhase = .needsRegistration
            } else {
                // Session without a profile (signup succeeded, the
                // profile insert never landed) → complete it via
                // the registration form.
                accountPhase = .needsRegistration
            }
        } catch let error as GGBackendError {
            if error == .offline {
                connectionOnline = false
                // With a cached profile we can still show the app;
                // polling will recover once we're back online.
                if myProfile != nil {
                    accountPhase = .ready
                    startPolling()
                } else {
                    accountPhase = .needsRegistration
                }
            } else if error == .sessionExpired {
                accountPhase = .needsRegistration
            } else {
                accountPhase = .needsRegistration
            }
        } catch {
            accountPhase = .needsRegistration
        }
    }

    /// RootView calls this when the app returns to the foreground.
    func appBecameActive() async {
        guard accountPhase == .ready else {
            if accountPhase == .checking { await bootstrap() }
            return
        }
        await refreshInbox()
        if let open = openChatID, isServerChat(open) {
            await refreshConversation(chatID: open)
        }
    }

    private func route(for profile: GGProfile) {
        if profile.activated {
            accountPhase = .ready
        } else if BuildVariant.isAdmin {
            accountPhase = .waitingAdmin
        } else {
            accountPhase = .needsCode
        }
    }

    private func adoptProfile(_ profile: GGProfile) {
        myProfile = profile
        profileName = profile.displayName
        persist(profile, key: Keys.myProfile)
    }

    // MARK: - Registration

    /// Username rules: lowercased, 3–20 chars of [a-z0-9._-].
    static func normalizedUsername(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidUsername(_ username: String) -> Bool {
        guard username.count >= 3, username.count <= 20 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        return username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Full registration. Returns nil on success (the phase has
    /// been routed), otherwise a user-facing German error text.
    /// - Normal build: name + username + invite code.
    /// - Admin build: name + username only (code == "").
    func register(displayName: String, username rawUsername: String, code rawCode: String) async -> String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = Store.normalizedUsername(rawUsername)
        let code = InviteCode.normalize(rawCode)
        guard !name.isEmpty else { return "Bitte gib einen Anzeigenamen ein." }
        guard Store.isValidUsername(username) else {
            return "Der Benutzername braucht 3–20 Zeichen: nur Kleinbuchstaben, Ziffern, Punkt, Unterstrich oder Bindestrich."
        }
        if !BuildVariant.isAdmin {
            guard InviteCode.isValid(code) else {
                return "Der Code hat nicht das richtige Format — er sieht so aus: GG-XXXXXX-XXXXXX."
            }
        }
        do {
            if !(await client.hasSession) {
                _ = try await client.signUpAnonymous()
            } else {
                _ = try await client.validAccessToken()
            }
            connectionOnline = true
            var profile = try await client.fetchOwnProfile()
            if profile == nil {
                try await client.createProfile(username: username, displayName: name)
                profile = try await client.fetchOwnProfile()
            }
            guard let profile else {
                return "Dein Profil konnte nicht angelegt werden. Bitte versuch es erneut."
            }
            adoptProfile(profile)

            if BuildVariant.isAdmin {
                route(for: profile)
                if accountPhase == .ready {
                    startPolling()
                    await refreshInbox()
                }
                return nil
            }

            // Normal build: redeem the code server-side.
            let redeemed = try await client.redeemInvite(code: code)
            if !redeemed {
                accountPhase = .needsCode
                return "Code ungültig oder schon benutzt. Prüfe den Code oder frag nach einem neuen."
            }
            if let refreshed = try await client.fetchOwnProfile() {
                adoptProfile(refreshed)
                route(for: refreshed)
            } else {
                route(for: profile)
            }
            if accountPhase == .ready {
                startPolling()
                await refreshInbox()
            }
            return nil
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            return error.german
        } catch {
            return "Unerwarteter Fehler. Bitte versuch es erneut."
        }
    }

    /// Code-only step for a returning, not-yet-activated user
    /// (normal build). Returns nil on success.
    func submitCode(_ rawCode: String) async -> String? {
        let code = InviteCode.normalize(rawCode)
        guard InviteCode.isValid(code) else {
            return "Der Code hat nicht das richtige Format — er sieht so aus: GG-XXXXXX-XXXXXX."
        }
        do {
            let redeemed = try await client.redeemInvite(code: code)
            connectionOnline = true
            if !redeemed {
                return "Code ungültig oder schon benutzt. Prüfe den Code oder frag nach einem neuen."
            }
            if let profile = try await client.fetchOwnProfile() {
                adoptProfile(profile)
                route(for: profile)
                if accountPhase == .ready {
                    startPolling()
                    await refreshInbox()
                }
            }
            return nil
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            return error.german
        } catch {
            return "Unerwarteter Fehler. Bitte versuch es erneut."
        }
    }

    /// Admin "Status prüfen": re-fetch the profile and re-route
    /// (the flags are flipped server-side by the parent).
    func refreshMyStatus() async {
        do {
            if let profile = try await client.fetchOwnProfile() {
                connectionOnline = true
                adoptProfile(profile)
                route(for: profile)
                if accountPhase == .ready {
                    startPolling()
                    await refreshInbox()
                }
            }
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            showBanner(error.german)
        } catch {
            showBanner("Status konnte nicht geprüft werden.")
        }
    }

    /// Settings → name editing: PATCHes the server profile
    /// (display_name is the one field clients may change).
    func updateDisplayName(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            if let updated = try await client.updateDisplayName(name) {
                adoptProfile(updated)
            } else {
                profileName = name
            }
        } catch {
            showBanner("Name konnte nicht gespeichert werden.")
        }
    }

    // MARK: - Polling

    /// List poll ≈ every 5 s, open-chat poll ≈ every 2 s. Both
    /// run only while the account is ready.
    private func startPolling() {
        stopPolling()
        listPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.accountPhase == .ready else { continue }
                await self.refreshInbox()
            }
        }
        chatPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.accountPhase == .ready,
                      let open = self.openChatID, self.isServerChat(open) else { continue }
                await self.refreshConversation(chatID: open)
            }
        }
    }

    private func stopPolling() {
        listPollTask?.cancel()
        chatPollTask?.cancel()
        listPollTask = nil
        chatPollTask = nil
    }

    // MARK: - Server chats

    func isServerChat(_ chatID: String) -> Bool {
        chatID.hasPrefix(Store.serverChatPrefix)
    }

    func partnerID(forChat chatID: String) -> String? {
        guard isServerChat(chatID) else { return nil }
        return String(chatID.dropFirst(Store.serverChatPrefix.count))
    }

    static func chatID(forPartner partnerID: String) -> String {
        serverChatPrefix + partnerID
    }

    /// Deterministic avatar color from the username (stable across
    /// launches and devices).
    static func colorIndex(for username: String) -> Int {
        let sum = username.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % 8 // Theme.avatarColors.count
    }

    /// Fetches the newest 200 messages I'm part of, derives the
    /// conversation list (partners, previews, unread counts) and
    /// refreshes the per-chat caches.
    func refreshInbox() async {
        guard !Store.isUITestMode else { return }
        guard accountPhase == .ready, let me = myProfile else { return }
        do {
            let recent = try await client.fetchRecentMessages(myID: me.id)
            connectionOnline = true

            var byPartner: [String: [GGServerMessage]] = [:]
            for message in recent {
                let partner = message.senderID == me.id ? message.recipientID : message.senderID
                byPartner[partner, default: []].append(message)
            }

            // Resolve profiles for partners we don't know yet.
            let unknown = byPartner.keys.filter { id in
                id != me.id && !partners.contains { $0.id == id }
            }
            if !unknown.isEmpty {
                let fetched = try await client.fetchProfiles(ids: Array(unknown))
                if !fetched.isEmpty {
                    partners.append(contentsOf: fetched)
                    persist(partners, key: Keys.partners)
                }
            }

            // Merge into the per-chat caches + unread counts.
            var unreadByChat: [String: Int] = [:]
            for (partner, msgs) in byPartner {
                if let forgottenAt = forgottenPartners[partner],
                   !(msgs.first?.createdAt ?? .distantPast > forgottenAt) {
                    continue // still deleted; nothing newer arrived
                }
                let chatID = Store.chatID(forPartner: partner)
                let converted = msgs.map { toLocal($0, myID: me.id) }.sorted { $0.date < $1.date }
                // The inbox window (200) may be a subset of a long
                // history — keep whichever side knows more.
                if converted.count >= (serverMessages[chatID]?.count ?? 0) {
                    serverMessages[chatID] = converted
                }
                let readUpTo = lastRead[partner] ?? .distantPast
                unreadByChat[chatID] = msgs.filter {
                    $0.recipientID == me.id && $0.createdAt > readUpTo
                }.count
            }

            rebuildChats(unreadByChat: unreadByChat)
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
        } catch {
            // Transient — the next poll retries.
        }
    }

    /// Reloads one conversation's full history from the server.
    func refreshConversation(chatID: String) async {
        guard !Store.isUITestMode else { return }
        guard let me = myProfile,
              let partner = partnerID(forChat: chatID) else { return }
        do {
            let history = try await client.fetchConversation(myID: me.id, partnerID: partner)
            connectionOnline = true
            let converted = history.map { toLocal($0, myID: me.id) }.sorted { $0.date < $1.date }
            serverMessages[chatID] = converted
            // Drop optimistic copies the server now confirms
            // (same body, mine, within two minutes).
            if let pending = pendingMessages[chatID] {
                pendingMessages[chatID] = pending.filter { optimistic in
                    !converted.contains {
                        $0.isMine && $0.text == optimistic.text
                            && abs($0.date.timeIntervalSince(optimistic.date)) < 120
                    }
                }
            }
            if openChatID == chatID {
                if let latestIncoming = history.last(where: { $0.recipientID == me.id }) {
                    lastRead[partner] = max(lastRead[partner] ?? .distantPast, latestIncoming.createdAt)
                }
                setUnread(chatID: chatID, count: 0)
            }
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
        } catch {
            // Transient — the next poll retries.
        }
    }

    /// Opens (or creates) the 1:1 server chat with a profile and
    /// navigates to it. Used by Kontakte search + partner rows.
    func openServerChat(with profile: GGProfile) {
        if !partners.contains(where: { $0.id == profile.id }) {
            partners.append(profile)
            persist(partners, key: Keys.partners)
        }
        forgottenPartners[profile.id] = nil
        rebuildChats()
        selectedTab = 0
        pendingChatID = Store.chatID(forPartner: profile.id)
        Task { await refreshConversation(chatID: Store.chatID(forPartner: profile.id)) }
    }

    /// Compatibility entry for the views that still pass a
    /// GGContact around (Kontakte list, pickers, call rows): every
    /// contact IS a server partner in v2.0.
    func openChat(with contact: GGContact) {
        if let profile = partners.first(where: { $0.id == contact.id }) {
            openServerChat(with: profile)
        }
    }

    /// Send in a server chat: optimistic append, then POST; the
    /// next poll reconciles (and drops the optimistic copy).
    func sendServerMessage(chatID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let me = myProfile,
              let partner = partnerID(forChat: chatID) else { return }
        let optimistic = GGMessage(chatID: chatID, isMine: true, text: trimmed, date: Date())
        pendingMessages[chatID, default: []].append(optimistic)
        objectWillChange.send()
        if Store.isUITestMode {
            // QA mode: keep the optimistic copy on screen,
            // never touch the network.
            return
        }
        Task {
            do {
                _ = try await client.sendMessage(myID: me.id, partnerID: partner, body: trimmed)
                connectionOnline = true
                await refreshConversation(chatID: chatID)
            } catch let error as GGBackendError {
                pendingMessages[chatID]?.removeAll { $0.id == optimistic.id }
                objectWillChange.send()
                if error == .offline { connectionOnline = false }
                showBanner("Nachricht konnte nicht gesendet werden. " + error.german)
            } catch {
                pendingMessages[chatID]?.removeAll { $0.id == optimistic.id }
                objectWillChange.send()
                showBanner("Nachricht konnte nicht gesendet werden.")
            }
        }
    }

    private func toLocal(_ message: GGServerMessage, myID: String) -> GGMessage {
        GGMessage(
            id: UUID(uuidString: message.id) ?? UUID(),
            chatID: Store.chatID(forPartner: message.senderID == myID ? message.recipientID : message.senderID),
            isMine: message.senderID == myID,
            text: message.body,
            date: message.createdAt
        )
    }

    // MARK: - Chat list derivation

    /// Rebuilds `chats` + `contacts` from the partner list.
    /// `unreadByChat` (from a fresh inbox fetch) wins; otherwise a
    /// chat keeps the unread count it already shows.
    private func rebuildChats(unreadByChat: [String: Int] = [:]) {
        var result: [GGChat] = [
            GGChat(id: Store.savedChatID, contactID: nil, title: "Gespeichertes", colorIndex: 0),
        ]
        for partner in partners {
            let chatID = Store.chatID(forPartner: partner.id)
            let existing = chats.first { $0.id == chatID }
            result.append(GGChat(
                id: chatID,
                contactID: partner.id,
                title: partner.displayName,
                colorIndex: Store.colorIndex(for: partner.username),
                isMuted: false,
                unread: unreadByChat[chatID] ?? existing?.unread ?? 0
            ))
        }
        chats = result
        contacts = partners.map {
            GGContact(id: $0.id,
                      name: $0.displayName,
                      status: "@\($0.username)",
                      colorIndex: Store.colorIndex(for: $0.username))
        }
    }

    private func setUnread(chatID: String, count: Int) {
        guard let idx = chats.firstIndex(where: { $0.id == chatID }),
              chats[idx].unread != count else { return }
        chats[idx].unread = count
    }

    // MARK: Lookups (view-facing)

    func contact(id: String) -> GGContact? {
        contacts.first { $0.id == id }
    }

    func chat(id: String) -> GGChat? {
        chats.first { $0.id == id }
    }

    /// Merged message list for a chat: local store for
    /// "Gespeichertes", server cache + optimistic pendings for
    /// server chats.
    func messages(for chatID: String) -> [GGMessage] {
        if chatID == Store.savedChatID {
            return (messages[chatID] ?? []).sorted { $0.date < $1.date }
        }
        let confirmed = serverMessages[chatID] ?? []
        let pending = pendingMessages[chatID] ?? []
        return (confirmed + pending).sorted { $0.date < $1.date }
    }

    func lastMessage(for chatID: String) -> GGMessage? {
        messages(for: chatID).last
    }

    /// Chats sorted by latest activity (chat list order).
    var sortedChats: [GGChat] {
        chats.sorted {
            (lastMessage(for: $0.id)?.date ?? .distantPast)
                > (lastMessage(for: $1.id)?.date ?? .distantPast)
        }
    }

    // MARK: Chat actions

    func markRead(chatID: String) {
        if let partner = partnerID(forChat: chatID) {
            let latest = (serverMessages[chatID] ?? []).map(\.date).max()
            if let latest {
                lastRead[partner] = max(lastRead[partner] ?? .distantPast, latest)
            }
        }
        setUnread(chatID: chatID, count: 0)
    }

    func deleteChat(id: String) {
        // "Gespeichertes" is a system entry (like Telegram's Saved
        // Messages) — it always stays.
        guard id != Store.savedChatID else { return }
        if let partner = partnerID(forChat: id) {
            // Forget locally: the server keeps the history; the
            // chat reappears only if a newer message arrives.
            forgottenPartners[partner] = Date()
            partners.removeAll { $0.id == partner }
            persist(partners, key: Keys.partners)
            serverMessages[id] = nil
            pendingMessages[id] = nil
        } else {
            messages[id] = nil
        }
        if openChatID == id { openChatID = nil }
        rebuildChats()
    }

    /// LOCAL send — only "Gespeichertes" (and, defensively, any
    /// non-server chat) uses this path. Server chats go through
    /// sendServerMessage(chatID:text:).
    func sendMessage(chatID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isServerChat(chatID) {
            sendServerMessage(chatID: chatID, text: trimmed)
            return
        }
        var list = messages[chatID] ?? []
        list.append(GGMessage(chatID: chatID, isMine: true, text: trimmed, date: Date()))
        messages[chatID] = list
    }

    // MARK: - Kontakte search

    /// Debounced username search (the view waits ~350 ms via
    /// .task(id:)). Under 2 chars → no results, no request.
    func performSearch(_ rawTerm: String) async {
        guard !Store.isUITestMode else {
            // QA mode: Kontakte shows the sample partners; no search.
            searchResults = []
            isSearching = false
            return
        }
        let term = Store.normalizedUsername(rawTerm)
        guard term.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        // Only [a-z0-9._-] can reach the filter (isValidUsername's
        // alphabet minus the length rule) — strip anything else so
        // the PostgREST filter syntax cannot be broken.
        let sanitized = term.filter { "abcdefghijklmnopqrstuvwxyz0123456789._-".contains($0) }
        guard sanitized.count >= 2 else {
            searchResults = []
            return
        }
        do {
            let found = try await client.searchProfiles(term: sanitized)
            connectionOnline = true
            // Never offer myself as a contact.
            searchResults = found.filter { $0.id != myProfile?.id }
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            searchResults = []
        } catch {
            searchResults = []
        }
    }

    // MARK: - Admin: server invite codes

    /// Loads the server code list + the display names of users who
    /// redeemed codes (admin only — RLS enforces it server-side).
    func refreshAdminCodes() async {
        guard BuildVariant.isAdmin, myProfile?.isAdmin == true else { return }
        adminBusy = true
        defer { adminBusy = false }
        do {
            let codes = try await client.fetchInviteCodes()
            connectionOnline = true
            serverCodes = codes
            let usedIDs = Array(Set(codes.compactMap(\.usedBy)))
            if !usedIDs.isEmpty {
                let profiles = try await client.fetchProfiles(ids: usedIDs)
                var names: [String: String] = [:]
                for profile in profiles {
                    names[profile.id] = profile.displayName
                }
                codeUsedByNames = names
            }
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            showBanner(error.german)
        } catch {
            showBanner("Codes konnten nicht geladen werden.")
        }
    }

    /// Creates a code on the server and reloads the list.
    /// Returns nil on success, else a German error text.
    func createServerCode() async -> String? {
        adminBusy = true
        defer { adminBusy = false }
        do {
            _ = try await client.createInviteCode()
            connectionOnline = true
            await refreshAdminCodes()
            return nil
        } catch let error as GGBackendError {
            if error == .offline { connectionOnline = false }
            return error.german
        } catch {
            return "Code konnte nicht erstellt werden."
        }
    }

    // MARK: - Banner

    func showBanner(_ text: String) {
        bannerText = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.bannerText = nil
        }
    }

    // MARK: Calls (local only)

    /// Logs a finished outgoing call. Calls longer than 5 s count
    /// as answered (duration shown); shorter ones plainly.
    func logOutgoingCall(contactID: String, durationSec: Int) {
        calls.insert(
            GGCall(contactID: contactID, date: Date(), direction: .outgoing,
                   missed: false, durationSec: durationSec > 5 ? durationSec : 0),
            at: 0
        )
    }

    var sortedCalls: [GGCall] {
        calls.sorted { $0.date > $1.date }
    }

    // MARK: Persistence helpers

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func persistCodable<T: Encodable>(_ value: T, key: String) {
        persist(value, key: key)
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
