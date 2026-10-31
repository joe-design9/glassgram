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
        // v2 key set (since 1.1.0): the app starts EMPTY like a real
        // messenger — the v1 keys held demo seed content and are
        // deliberately abandoned so an upgrade starts clean.
        static let contacts = "gg.contacts.v2"
        static let chats = "gg.chats.v2"
        static let messages = "gg.messages.v2"
        static let calls = "gg.calls.v2"
        static let settings = "gg.settings.v2"
        static let adminCodes = "gg.adminCodes.v1"
        static let initialized = "gg.initialized.v2"
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
        gatePassed = defaults.bool(forKey: Keys.gatePassed)

        #if ADMIN_BUILD
        // The admin build belongs to the owner — there is NO invite
        // gate in this variant. It starts straight into the app with
        // the stored (or default) profile name; codes are only
        // created and handed out from the admin panel in Settings.
        // (didSet does not fire during init — persist explicitly.)
        gatePassed = true
        defaults.set(true, forKey: Keys.gatePassed)
        #endif

        if defaults.bool(forKey: Keys.initialized),
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
            setupEmptyState()
            defaults.set(true, forKey: Keys.initialized)
        }

        // Admin build: make sure the code manager has its three
        // pre-generated codes so one can be handed out immediately.
        if BuildVariant.isAdmin && adminCodes.isEmpty {
            adminCodes = (0..<3).map {
                AdminCode(code: InviteCode.seededCode($0),
                          createdAt: Date().addingTimeInterval(Double(-$0) * 3600),
                          status: "frei")
            }
            // Same init-phase caveat as in setupEmptyState():
            // persist explicitly.
            persist(adminCodes, key: Keys.adminCodes)
        }
    }

    // MARK: First launch — the app starts EMPTY

    /// No demo content: a real messenger opens with no chats, no
    /// contacts and no call history. The single system entry is
    /// "Gespeichertes" (saved messages — chat with yourself, empty).
    private func setupEmptyState() {
        contacts = []
        chats = [
            GGChat(id: Store.savedChatID, contactID: nil, title: "Gespeichertes", colorIndex: 0),
        ]
        messages = [:]
        calls = []

        // didSet does NOT fire during initialization — persist
        // explicitly, or the second launch would re-run this setup
        // and wipe the user's data.
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
        // "Gespeichertes" is a system entry (like Telegram's Saved
        // Messages) — it always stays.
        guard id != Store.savedChatID else { return }
        chats.removeAll { $0.id == id }
        messages[id] = nil
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
    }

    private func appendMessage(_ message: GGMessage) {
        var list = messages[message.chatID] ?? []
        list.append(message)
        messages[message.chatID] = list
    }

    // MARK: Contacts

    /// Creates a contact AND its (empty) 1:1 chat — the "Neuer
    /// Kontakt" flow in the Kontakte tab. Both are persisted via the
    /// didSet observers; returns the new contact so the caller can
    /// navigate straight into the chat.
    @discardableResult
    func addContact(name: String) -> GGContact {
        let contact = GGContact(
            id: "c-\(UUID().uuidString.lowercased())",
            name: name,
            status: "GlassGram-Kontakt",
            colorIndex: contacts.count % 8 // Theme.avatarColors.count
        )
        contacts.append(contact)
        let chatID = "chat-\(contact.id)"
        if !chats.contains(where: { $0.id == chatID }) {
            chats.append(GGChat(id: chatID, contactID: contact.id,
                                title: contact.name, colorIndex: contact.colorIndex))
            if messages[chatID] == nil { messages[chatID] = [] }
        }
        return contact
    }

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
