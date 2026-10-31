import SwiftUI

/// Tab 1 — Chats: header, glass search, folder filter pill and the
/// chat list, modeled on the reference screenshots.
struct ChatsListView: View {
    @EnvironmentObject private var store: Store
    @State private var path: [String] = []
    @State private var searchText = ""
    @State private var folderFilter: String? = nil // nil = "Alle"
    @State private var editMode: EditMode = .inactive
    @State private var showContactPicker = false

    /// The custom folder name, taken from the chats that carry one.
    private var folderName: String {
        store.chats.compactMap(\.folder).first ?? "Favoriten"
    }

    /// True once any chat besides "Gespeichertes" exists.
    private var hasRealChats: Bool {
        store.chats.contains { !$0.isSavedMessages }
    }

    private var visibleChats: [GGChat] {
        store.sortedChats.filter { chat in
            if let folderFilter, chat.folder != folderFilter { return false }
            if !searchText.isEmpty,
               !chat.title.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    /// Height the floating chrome occupies — the list's top
    /// content margin, so the first row starts below the glass
    /// while everything still scrolls UNDER it.
    private var listTopInset: CGFloat {
        store.chats.contains(where: { $0.folder != nil }) ? 176 : 126
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                chatList
                // Floating chrome (v2.0.0): header, search and the
                // folder filter hover OVER the list — rows scroll
                // beneath their glass and refract in it, like
                // Telegram's Liquid Glass bars. The folder filter
                // only appears once a chat actually carries a
                // folder — an empty app shows no pill.
                VStack(spacing: 10) {
                    header
                    searchField
                    if store.chats.contains(where: { $0.folder != nil }) {
                        filterPill
                    }
                }
                .padding(.top, 6)
            }
            .background { DepthBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { chatID in
                if let chat = store.chat(id: chatID) {
                    ChatView(chat: chat)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerSheet { contact in
                    showContactPicker = false
                    store.openChat(with: contact)
                }
            }
        }
        .onAppear { consumePendingChat() }
        .onChange(of: store.pendingChatID) { _, _ in
            consumePendingChat()
        }
        .dismissKeyboardOnTap()
    }

    /// Opens a chat requested through `store.pendingChatID`
    /// (contact tap in another tab, saved-chat shortcut, QA
    /// screenshot targeting). Called from onAppear too:
    /// onChange never fires for a value that was already set
    /// before this view existed — the Kontakte-first flow and
    /// the QA seeding both set it up front.
    private func consumePendingChat() {
        guard let chatID = store.pendingChatID else { return }
        store.pendingChatID = nil
        if path.last != chatID {
            path.append(chatID)
        }
    }

    // MARK: Header

    private var header: some View {
        // Grouped glass (v2.0.0): the pill and the round button
        // share a GlassEffectContainer so their specular
        // highlights blend like Apple's grouped glass.
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Text(editMode.isEditing ? "Fertig" : "Bearbeiten")
                        .font(.system(size: 15.5))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .glassPill(interactive: true)

                Spacer()

                Text("Chats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    showContactPicker = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                }
                .glassCircle()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Suchen", text: $searchText)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPill()
        .padding(.horizontal, 16)
    }

    // MARK: Folder filter

    private var filterPill: some View {
        HStack(spacing: 2) {
            filterButton(title: "Alle", value: nil)
            filterButton(title: folderName, value: folderName)
        }
        .padding(3)
        .glassPill()
        .padding(.horizontal, 16)
    }

    private func filterButton(title: String, value: String?) -> some View {
        Button {
            folderFilter = value
        } label: {
            Text(title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if folderFilter == value {
                        Capsule()
                            .glassEffect(.clear.tint(Theme.accent.opacity(0.30)),
                                         in: .capsule)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var chatList: some View {
        List {
            ForEach(visibleChats) { chat in
                // DIRECT tap navigation (v1.1.0 fix): the whole row is
                // a plain Button that pushes the chat id onto the
                // NavigationStack path itself. The old
                // NavigationLink-in-List rows rendered a ">" chevron
                // (Telegram has none) and their taps were unreliable —
                // together with the screen-root tap gesture (removed
                // in Keyboard.swift) they produced dead rows.
                Button {
                    // In edit mode a tap must NOT navigate — deleting
                    // happens via the list's edit controls / swipe.
                    guard !editMode.isEditing else { return }
                    if path.last != chat.id {
                        path.append(chat.id)
                    }
                } label: {
                    ChatRow(chat: chat)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.white.opacity(0.12))
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                for index in offsets {
                    store.deleteChat(id: visibleChats[index].id)
                }
            }

            if visibleChats.isEmpty {
                Text(searchText.isEmpty
                        ? "Keine Chats in dieser Auswahl."
                        : "Keine Treffer für „\(searchText)“.")
                    .foregroundStyle(Theme.secondaryText)
                    .font(.system(size: 15))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Fresh-install empty state: only "Gespeichertes" exists.
            if !hasRealChats && searchText.isEmpty && folderFilter == nil {
                chatsEmptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 40, leading: 16, bottom: 6, trailing: 16))
            }

            // Keeps the last rows clear of the floating tab bar.
            Color.clear
                .frame(height: 84)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, listTopInset, for: .scrollContent)
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Empty state (Telegram style)

    private var chatsEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "message.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
                .frame(width: 92, height: 92)
                .glassCircle(interactive: false)
            Text("Noch keine Chats")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
            Text("Suche im Kontakte-Tab nach einem Benutzernamen, um deine erste Unterhaltung zu starten.")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                store.selectedTab = 1 // Kontakte
            } label: {
                Text("Kontakt suchen")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
            }
            .glassPill(interactive: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chat row

struct ChatRow: View {
    @EnvironmentObject private var store: Store
    let chat: GGChat

    var body: some View {
        let last = store.lastMessage(for: chat.id)
        HStack(spacing: 12) {
            if chat.isSavedMessages {
                SavedAvatarView(size: 54)
            } else {
                AvatarView(title: chat.title, colorIndex: chat.colorIndex, size: 54)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(chat.title)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if chat.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Text(previewText(last: last))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                if let last {
                    Text(TimeFormat.list(last.date))
                        .font(.system(size: 13))
                        .foregroundStyle(chat.unread > 0 ? Theme.accent : Theme.secondaryText)
                }
                if chat.unread > 0 {
                    Text(chat.unread > 999 ? "999+" : "\(chat.unread)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(chat.isMuted ? Color(white: 0.35) : Theme.accent, in: Capsule())
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func previewText(last: GGMessage?) -> String {
        guard let last else { return "Keine Nachrichten" }
        return (last.isMine ? "Du: " : "") + last.text
    }
}

// MARK: - Contact picker (compose button)

struct ContactPickerSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let onPick: (GGContact) -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.contacts.isEmpty {
                    Text("Noch keine Chat-Partner. Suche im Kontakte-Tab nach einem Benutzernamen.")
                        .foregroundStyle(Theme.secondaryText)
                        .font(.system(size: 15))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.contacts) { contact in
                    Button {
                        onPick(contact)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(title: contact.name, colorIndex: contact.colorIndex, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .foregroundStyle(.white)
                                    .font(.system(size: 16))
                                Text(contact.status)
                                    .foregroundStyle(Theme.secondaryText)
                                    .font(.system(size: 13.5))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { DepthBackdrop() }
            .navigationTitle("Neuer Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationBackground(.black)
    }
}
