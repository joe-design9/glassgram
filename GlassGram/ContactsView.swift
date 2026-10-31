import SwiftUI

/// Tab 2 — Kontakte: "Freunde einladen" (share sheet), "Neuer
/// Kontakt" (creates a contact + its empty 1:1 chat) and the contact
/// list. Tapping a contact opens (or creates) its 1:1 chat — the
/// whole row is the tap target, exactly like in the chat list.
struct ContactsView: View {
    @EnvironmentObject private var store: Store
    @State private var showShare = false
    @State private var showNewContact = false
    @State private var searchText = ""

    private var visibleContacts: [GGContact] {
        store.contacts
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
        .sheet(isPresented: $showNewContact) {
            NewContactSheet { name in
                showNewContact = false
                let contact = store.addContact(name: name)
                // Straight into the fresh, empty 1:1 chat.
                store.openChat(with: contact)
            }
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.black)
            .listRowSeparatorTint(.white.opacity(0.12))

            Button {
                showNewContact = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48)
                    Text("Neuer Kontakt")
                        .font(.system(size: 16.5))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.black)
            .listRowSeparatorTint(.white.opacity(0.12))

            if visibleContacts.isEmpty {
                Text(store.contacts.isEmpty && searchText.isEmpty
                        ? "Noch keine Kontakte. Tippe auf „Neuer Kontakt“, um deinen ersten Kontakt anzulegen."
                        : "Keine Treffer für „\(searchText)“.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.black)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(visibleContacts) { contact in
                        Button {
                            // Finds the 1:1 chat or creates it.
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
                        .listRowBackground(Color.black)
                        .listRowSeparatorTint(.white.opacity(0.12))
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                } header: {
                    Text("Sortierung: Name")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(white: 0.45))
                }
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

// MARK: - New contact sheet

struct NewContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onCreate: (String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Name des Kontakts", text: $name)
                    .foregroundStyle(.white)
                    .font(.system(size: 17))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                Text("Der Kontakt und ein leerer Chat mit ihm werden auf diesem iPhone angelegt — ganz ohne Server.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .padding(20)
            .background(Color.black)
            .navigationTitle("Neuer Kontakt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        guard !trimmedName.isEmpty else { return }
                        onCreate(trimmedName)
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationBackground(.black)
        .dismissKeyboardOnTap()
    }
}
