import Foundation

/// Central app state. EVERYTHING is local: chats, messages, contacts,
/// calls, settings, profile and (admin) invite codes live as JSON in
/// UserDefaults. No network, no account, no server.
@MainActor
final class Store: ObservableObject {
    static let savedChatID = "saved"

    private enum Keys {
        static let profileName = "gg.profileName"
        static let gatePassed = "gg.gatePassed"
        static let contacts = "gg.contacts.v1"
        static let chats = "gg.chats.v1"
        static let messages = "gg.messages.v1"
        static let calls = "gg.calls.v1"
        static let settings = "gg.settings.v1"
        static let adminCodes = "gg.adminCodes.v1"
        static let seeded = "gg.seeded.v1"
    }

    // MARK: Published state

    @Published var profileName: String = "Joel" {
        didSet { UserDefaults.standard.set(profileName, forKey: Keys.profileName) }
    }

    @Published var gatePassed: Bool = false {
        didSet { UserDefaults.standard.set(gatePassed, forKey: Keys.gatePassed) }
    }

    @Published var contacts: [GGContact] = [] {
        didSet { persist(contacts, key: Keys.contacts) }
    }

    @Published var chats: [GGChat] = [] {
        didSet { persist(chats, key: Keys.chats) }
    }

    @Published var messages: [String: [GGMessage]] = [:] {
        didSet { persist(messages, key: Keys.messages) }
    }

    @Published var calls: [GGCall] = [] {
        didSet { persist(calls, key: Keys.calls) }
    }

    @Published var settings: GGSettings = GGSettings() {
        didSet { persist(settings, key: Keys.settings) }
    }

    @Published var adminCodes: [AdminCode] = [] {
        didSet { persist(adminCodes, key: Keys.adminCodes) }
    }

    /// Chats whose partner is currently "typing" (demo auto-reply).
    @Published private(set) var typingChatIDs: Set<String> = []

    /// The chat currently on screen, if any (drives unread + tab bar).
    @Published var openChatID: String?

    /// Set by other tabs ("open this chat") — ChatsListView consumes it.
    @Published var pendingChatID: String?

    /// Selected main tab (RootView binds to this so tabs can jump).
    @Published var selectedTab: Int = 0

    private var pendingReplies: Set<String> = []

    // MARK: Init

    init() {
        let defaults = UserDefaults.standard
        profileName = defaults.string(forKey: Keys.profileName) ?? "Joel"
        gatePassed = defaults.bool(forKey: Keys.gatePassed)

        if defaults.bool(forKey: Keys.seeded),
           let storedContacts: [GGContact] = load(Keys.contacts),
           let storedChats: [GGChat] = load(Keys.chats) {
            contacts = storedContacts
            chats = storedChats
            messages = load(Keys.messages) ?? [:]
            calls = load(Keys.calls) ?? []
            if let storedSettings: GGSettings = load(Keys.settings) {
                settings = storedSettings
            }
            adminCodes = load(Keys.adminCodes) ?? []
        } else {
            seed()
            defaults.set(true, forKey: Keys.seeded)
        }

        // Admin build: make sure the code manager has its three
        // pre-generated codes so one can be handed out immediately.
        if BuildVariant.isAdmin && adminCodes.isEmpty {
            adminCodes = (0..<3).map {
                AdminCode(code: InviteCode.seededCode($0),
                          createdAt: Date().addingTimeInterval(Double(-$0) * 3600),
                          status: "frei")
            }
            // Same init-phase caveat as in seed(): persist explicitly.
            persist(adminCodes, key: Keys.adminCodes)
        }
    }

    // MARK: Seeding (first launch)

    private func seed() {
        let now = Date()
        func minsAgo(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

        contacts = [
            GGContact(id: "stefan", name: "Stefan B", status: "zul. online gestern um 23:01", colorIndex: 0),
            GGContact(id: "silke", name: "Silke Vorwerk", status: "zul. online 28.10.26", colorIndex: 1),
            GGContact(id: "jana", name: "Jana", status: "zul. online 25.10.26", colorIndex: 2),
            GGContact(id: "mama", name: "Mama", status: "zul. online 20.10.26", colorIndex: 3),
            GGContact(id: "gloeckner", name: "Glöckner", status: "zul. online 19.10.26", colorIndex: 4),
            GGContact(id: "petra", name: "Petra", status: "zul. online 16.10.26", colorIndex: 5),
            GGContact(id: "cyberleek", name: "CyberLeek", status: "Kanal · 12 480 Abonnenten", colorIndex: 6, isChannel: true),
            GGContact(id: "gtagroup", name: "GTA 6 latest news", status: "Gruppe · 342 Mitglieder", colorIndex: 7, isGroup: true),
        ]

        chats = [
            GGChat(id: Store.savedChatID, contactID: nil, title: "Gespeichertes", colorIndex: 0),
            GGChat(id: "chat-gta", contactID: "gtagroup", title: "GTA 6 latest news", colorIndex: 7, isMuted: true, unread: 166, folder: "Favoriten"),
            GGChat(id: "chat-mama", contactID: "mama", title: "Mama", colorIndex: 3, unread: 2, folder: "Favoriten"),
            GGChat(id: "chat-stefan", contactID: "stefan", title: "Stefan B", colorIndex: 0),
            GGChat(id: "chat-cyberleek", contactID: "cyberleek", title: "CyberLeek", colorIndex: 6, isMuted: true),
            GGChat(id: "chat-jana", contactID: "jana", title: "Jana", colorIndex: 2),
        ]

        messages = [
            Store.savedChatID: [
                GGMessage(chatID: Store.savedChatID, isMine: true,
                          text: "Release-Checkliste: Preload ab 12.11. laden, Konsole freiräumen, Snacks kaufen.",
                          date: daysAgo(1)),
            ],
            "chat-gta": [
                GGMessage(chatID: "chat-gta", isMine: false,
                          text: "Dav ist der Gruppe beigetreten", date: minsAgo(64)),
                GGMessage(chatID: "chat-gta", isMine: false,
                          text: "Die neue Trailer-Analyse ist online — Link steht in der Gruppenbeschreibung.",
                          date: minsAgo(58)),
                GGMessage(chatID: "chat-gta", isMine: false,
                          text: "Noch 19 Tage bis Leonida. Wer ist beim Midnight-Launch dabei?",
                          date: minsAgo(41)),
            ],
            "chat-mama": [
                GGMessage(chatID: "chat-mama", isMine: true,
                          text: "Hallo Mama, ich melde mich am Wochenende!", date: daysAgo(1)),
                GGMessage(chatID: "chat-mama", isMine: false,
                          text: "Hallo Joel, denk bitte an den Anruf am Sonntag.", date: minsAgo(95)),
                GGMessage(chatID: "chat-mama", isMine: false,
                          text: "Und vergiss nicht, Brot mitzubringen.", date: minsAgo(94)),
            ],
            "chat-stefan": [
                GGMessage(chatID: "chat-stefan", isMine: false,
                          text: "Alles klar, bis morgen im Training. Bring die neuen Schuhe mit!",
                          date: daysAgo(1)),
            ],
            "chat-cyberleek": [
                GGMessage(chatID: "chat-cyberleek", isMine: false,
                          text: "Neues Video ist in Arbeit — heute Abend gibt es ein Update im Kanal.",
                          date: minsAgo(180)),
            ],
            "chat-jana": [
                GGMessage(chatID: "chat-jana", isMine: false,
                          text: "Der Zug hatte nur 5 Minuten Verspätung. Wunder geschehen also doch.",
                          date: daysAgo(2)),
            ],
        ]

        calls = [
            GGCall(contactID: "stefan", date: minsAgo(150), direction: .incoming, missed: true),
            GGCall(contactID: "mama", date: daysAgo(1), direction: .incoming, missed: false, durationSec: 184),
        ]

        // didSet does NOT fire during initialization — persist the
        // seed explicitly, or the second launch would re-seed and
        // wipe the user's data.
        persist(contacts, key: Keys.contacts)
        persist(chats, key: Keys.chats)
        persist(messages, key: Keys.messages)
        persist(calls, key: Keys.calls)
        persist(settings, key: Keys.settings)
    }

    // MARK: Lookups

    func contact(id: String) -> GGContact? {
        contacts.first { $0.id == id }
    }

    func chat(id: String) -> GGChat? {
        chats.first { $0.id == id }
    }

    func messages(for chatID: String) -> [GGMessage] {
        (messages[chatID] ?? []).sorted { $0.date < $1.date }
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
        guard let idx = chats.firstIndex(where: { $0.id == chatID }),
              chats[idx].unread != 0 else { return }
        chats[idx].unread = 0
    }

    func deleteChat(id: String) {
        chats.removeAll { $0.id == id }
        messages[id] = nil
        typingChatIDs.remove(id)
        pendingReplies.remove(id)
        if openChatID == id { openChatID = nil }
    }

    /// Opens the 1:1 chat for a contact (creating it on first use) and
    /// asks the Chats tab to navigate to it.
    func openChat(with contact: GGContact) {
        let chatID = "chat-\(contact.id)"
        if !chats.contains(where: { $0.id == chatID }) {
            chats.append(GGChat(id: chatID, contactID: contact.id,
                                title: contact.name, colorIndex: contact.colorIndex))
            if messages[chatID] == nil { messages[chatID] = [] }
        }
        selectedTab = 0
        pendingChatID = chatID
    }

    func sendMessage(chatID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendMessage(GGMessage(chatID: chatID, isMine: true, text: trimmed, date: Date()))
        if settings.vibrationEnabled {
            // Light tap feedback is handled by the view layer; the
            // setting is persisted and honored there.
        }
        if let chat = chat(id: chatID) {
            scheduleReplyIfNeeded(for: chat)
        }
    }

    private func appendMessage(_ message: GGMessage) {
        var list = messages[message.chatID] ?? []
        list.append(message)
        messages[message.chatID] = list
    }

    // MARK: Demo auto-replies

    /// A chat partner answers exactly once per burst of user messages,
    /// after ~1.2 s, with a "schreibt …" indicator in between.
    /// Saved-messages and channel chats never reply.
    private func scheduleReplyIfNeeded(for chat: GGChat) {
        guard !chat.isSavedMessages else { return }
        guard let contact = chat.contactID.flatMap({ contact(id: $0) }),
              !contact.isChannel else { return }
        guard !pendingReplies.contains(chat.id) else { return }
        pendingReplies.insert(chat.id)
        typingChatIDs.insert(chat.id)
        let chatID = chat.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            typingChatIDs.remove(chatID)
            pendingReplies.remove(chatID)
            // The chat may have been deleted in the meantime.
            guard self.chat(id: chatID) != nil else { return }
            let reply = self.nextReply(for: chatID)
            self.appendMessage(GGMessage(chatID: chatID, isMine: false, text: reply, date: Date()))
            if self.openChatID != chatID,
               let idx = self.chats.firstIndex(where: { $0.id == chatID }) {
                self.chats[idx].unread += 1
            }
        }
    }

    private func nextReply(for chatID: String) -> String {
        let pool = Store.replyPools[chatID] ?? Store.genericReplies
        let theirs = messages(for: chatID).filter { !$0.isMine }.count
        return pool[theirs % pool.count]
    }

    private static let genericReplies = [
        "Alles klar, danke dir!",
        "Okay, klingt gut.",
        "Ja, lass uns das so machen.",
        "Verstanden — ich melde mich später nochmal.",
    ]

    private static let replyPools: [String: [String]] = [
        "chat-mama": [
            "Das ist schön, mein Junge. Pass auf dich auf!",
            "Gut, dann bis Sonntag. Ich freu mich.",
            "Alles klar, hab ich mir notiert.",
        ],
        "chat-stefan": [
            "Perfekt, dann sehen wir uns morgen.",
            "Haha, genau so machen wir das.",
            "Alles klar, ich bring die Getränke mit.",
        ],
        "chat-jana": [
            "Stimmt, das war wirklich knapp diesmal.",
            "Okay, dann planen wir das am Wochenende.",
            "Gute Idee, schreib ich mir auf.",
        ],
        "chat-gta": [
            "Stark, danke für die Info!",
            "19. November kann kommen.",
            "Das wird im Kanal sicher auch gleich geteilt.",
        ],
    ]

    // MARK: Calls

    /// Logs a finished outgoing call. Calls longer than 5 s count as
    /// answered (duration shown); shorter ones are logged plainly.
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

    // MARK: Invite gate

    /// Returns true and permanently opens the gate when the code is
    /// valid (shared offline algorithm — see InviteCode.swift).
    func passGate(name: String, code: String) -> Bool {
        guard InviteCode.isValid(code) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { profileName = trimmed }
        gatePassed = true
        return true
    }

    // MARK: Admin codes

    func createAdminCode() {
        adminCodes.insert(
            AdminCode(code: InviteCode.generate(), createdAt: Date(), status: "frei"),
            at: 0
        )
    }

    func deleteAdminCode(id: UUID) {
        adminCodes.removeAll { $0.id == id }
    }

    func toggleAdminCodeStatus(id: UUID) {
        guard let idx = adminCodes.firstIndex(where: { $0.id == id }) else { return }
        adminCodes[idx].status = adminCodes[idx].status == "frei" ? "verteilt" : "frei"
    }

    /// Marks a code as handed out (used after Teilen/Kopieren).
    func markAdminCodeShared(id: UUID) {
        guard let idx = adminCodes.firstIndex(where: { $0.id == id }) else { return }
        adminCodes[idx].status = "verteilt"
    }

    // MARK: Persistence helpers

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
