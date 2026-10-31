import SwiftUI

/// Tab 2 — Kontakte: "Freunde einladen" (share sheet) plus the
/// contact list with last-seen lines, like the reference screenshot.
/// Tapping a contact opens (or creates) its 1:1 chat.
struct ContactsView: View {
    @EnvironmentObject private var store: Store
    @State private var showShare = false
    @State private var searchText = ""

    private var visibleContacts: [GGContact] {
        store.contacts
            .filter { !$0.isGroup }
            .filter {
                searchText.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Kontakte")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            searchField
            contactList
        }
        .background(Color.black)
        .dismissKeyboardOnTap()
        .sheet(isPresented: $showShare) {
            ShareSheet(items: ["Schau dir GlassGram an — der Messenger im Liquid-Glass-Design. Ganz schwarz, ganz Glas, komplett lokal."])
                .presentationBackground(.black)
        }
    }

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

    private var contactList: some View {
        List {
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
            }
            .listRowBackground(Color.black)
            .listRowSeparatorTint(.white.opacity(0.12))

            Section {
                ForEach(visibleContacts) { contact in
                    Button {
                        // Finds the seeded chat or creates the 1:1 chat.
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
                    .listRowBackground(Color.black)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            } header: {
                Text("Sortierung: zuletzt gesehen")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.45))
            }

            Color.clear
                .frame(height: 84)
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}
