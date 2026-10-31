import SwiftUI

/// Tab 2 — Kontakte (v2.0.0, server-backed):
///   - the search field queries the SERVER by username
///     (activated users only, debounced, min. 2 characters) —
///     tapping a result opens/creates the real 1:1 chat,
///   - below it, the people I already chat with (partners),
///   - "Freunde einladen" shares a text that explains the
///     invite-code step (codes come from an admin).
/// The local "Neuer Kontakt" dummy flow is gone — contacts are
/// real accounts now.
struct ContactsView: View {
    @EnvironmentObject private var store: Store
    @State private var showShare = false
    @State private var searchText = ""

    private var isSearching: Bool {
        Store.normalizedUsername(searchText).count >= 2
    }

    private var visiblePartners: [GGContact] {
        store.contacts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            contactList
            // Floating glass header + search over the list.
            VStack(spacing: 10) {
                Text("Kontakte")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                searchField
            }
            .padding(.top, 6)
        }
        .dismissKeyboardOnTap()
        .sheet(isPresented: $showShare) {
            ShareSheet(items: ["Lade dir GlassGram herunter — den Messenger im Liquid-Glass-Design. Zum Reinkommen brauchst du einen Einladungscode — schreib mir, ich gebe dir einen."])
                .presentationBackground(.black)
        }
        // Debounced server search: .task(id:) cancels and
        // restarts on every keystroke; the store waits ~350 ms
        // inside performSearch before it would query — the store
        // method itself enforces the 2-character minimum.
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await store.performSearch(searchText)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Benutzername suchen", text: $searchText)
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if store.isSearching {
                ProgressView()
                    .tint(Theme.secondaryText)
                    .scaleEffect(0.8)
            } else if !searchText.isEmpty {
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

    private var contactList: some View {
        List {
            if isSearching {
                searchResultsSection
            } else {
                inviteRow
                partnersSection
            }

            Color.clear
                .frame(height: 84)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 108, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Server search results

    private var searchResultsSection: some View {
        Group {
            if store.searchResults.isEmpty && !store.isSearching {
                Text(store.connectionOnline
                        ? "Keine Treffer für „\(Store.normalizedUsername(searchText))“. Der Benutzername muss exakt stimmen — frag die Person nach ihrem @Namen."
                        : "Keine Verbindung zum Server — Suche gerade nicht möglich.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(store.searchResults) { profile in
                Button {
                    store.openServerChat(with: profile)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(title: profile.displayName,
                                   colorIndex: Store.colorIndex(for: profile.username),
                                   size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                                .font(.system(size: 16.5))
                                .foregroundStyle(.white)
                            Text("@\(profile.username)")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.white.opacity(0.12))
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
    }

    // MARK: Invite + partners

    private var inviteRow: some View {
        Button {
            showShare = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48)
                Text("Freunde einladen")
                    .font(.system(size: 16.5))
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.white.opacity(0.12))
    }

    @ViewBuilder
    private var partnersSection: some View {
        if visiblePartners.isEmpty {
            Text("Noch keine Chat-Partner. Suche oben nach einem Benutzernamen, um deine erste Unterhaltung zu starten.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(visiblePartners) { contact in
                    Button {
                        // Finds the 1:1 server chat or creates it.
                        store.openChat(with: contact)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(title: contact.name, colorIndex: contact.colorIndex, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.system(size: 16.5))
                                    .foregroundStyle(.white)
                                Text(contact.status)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            } header: {
                Text("Deine Chat-Partner")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }
}
