import SwiftUI

/// Tab 3 — Anrufe: "Alle | Verpasst" filter and the local call
/// history. In v2.0 Anrufe stay purely local (no server calls):
/// the picker lists your chat partners, the call screen is an
/// in-app simulation — no real telephony.
struct CallsView: View {
    @EnvironmentObject private var store: Store
    @State private var filter: Filter = .alle
    @State private var showPicker = false
    @State private var callContact: GGContact?

    enum Filter: String, CaseIterable {
        case alle = "Alle"
        case verpasst = "Verpasst"
    }

    private var visibleCalls: [GGCall] {
        let all = store.sortedCalls
        switch filter {
        case .alle: return all
        case .verpasst: return all.filter { $0.missed }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Anrufe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                segmented

                if visibleCalls.isEmpty {
                    emptyState
                } else {
                    callList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPicker) {
                CallPickerSheet { contact in
                    showPicker = false
                    callContact = contact
                }
            }
            .fullScreenCover(item: $callContact) { contact in
                CallScreen(contact: contact) { duration in
                    store.logOutgoingCall(contactID: contact.id, durationSec: duration)
                    callContact = nil
                }
            }
        }
    }

    // MARK: Segmented filter

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Filter.allCases, id: \.self) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if filter == option {
                                Capsule().fill(.white.opacity(0.22))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassPill()
        .frame(maxWidth: 320)
    }

    // MARK: Empty state (mirrors the reference screenshot)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .frame(width: 110, height: 110)
                .glassCircle(interactive: false)
            Text("Deine letzten Sprach- und Videoanrufe werden hier angezeigt.")
                .font(.system(size: 15.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 50)
            Button {
                showPicker = true
            } label: {
                Label("Neuen Anruf starten", systemImage: "phone.badge.plus")
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: List

    private var callList: some View {
        List {
            ForEach(visibleCalls) { call in
                if let contact = store.contact(id: call.contactID) {
                    Button {
                        callContact = contact
                    } label: {
                        CallRow(call: call, contact: contact)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            Button {
                showPicker = true
            } label: {
                Label("Neuen Anruf starten", systemImage: "phone.badge.plus")
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Color.clear)

            Color.clear
                .frame(height: 84)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Call row

struct CallRow: View {
    let call: GGCall
    let contact: GGContact

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: contact.name, colorIndex: contact.colorIndex, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.system(size: 16, weight: call.missed ? .semibold : .regular))
                    .foregroundStyle(call.missed ? Theme.badgeRed : .white)
                HStack(spacing: 4) {
                    Image(systemName: call.direction == .outgoing
                            ? "phone.arrow.up.right.fill"
                            : "phone.arrow.down.left.fill")
                        .font(.system(size: 10))
                    Text(subtitle)
                        .font(.system(size: 13.5))
                }
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text(TimeFormat.call(call.date))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if call.missed { return "Verpasst" }
        let directionText = call.direction == .outgoing ? "Ausgehend" : "Eingehend"
        if call.durationSec > 0 {
            return "\(directionText) · \(TimeFormat.duration(call.durationSec))"
        }
        return directionText
    }
}

// MARK: - Contact picker for calls

struct CallPickerSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let onPick: (GGContact) -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.contacts.isEmpty {
                    Text("Noch keine Kontakte. Finde zuerst im Kontakte-Tab jemanden über die Benutzernamen-Suche und schreib ihm — dann kannst du ihn hier anrufen.")
                        .foregroundStyle(Theme.secondaryText)
                        .font(.system(size: 15))
                        .listRowBackground(Color.black)
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
                            Image(systemName: "phone.fill")
                                .foregroundStyle(Theme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.black)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Neuen Anruf starten")
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

// MARK: - Local call screen

/// In-app call UI (local simulation — no real telephony in v2.0):
/// connects after a beat, counts up, red button ends. The elapsed
/// seconds are reported back and logged by the caller.
struct CallScreen: View {
    @Environment(\.dismiss) private var dismiss
    let contact: GGContact
    let onEnd: (Int) -> Void

    @State private var elapsed = 0
    @State private var connected = false
    @State private var muted = false
    @State private var speakerOn = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 40)
                AvatarView(title: contact.name, colorIndex: contact.colorIndex, size: 110)
                Text(contact.name)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Text(connected ? TimeFormat.duration(elapsed) : "Verbinde …")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                HStack(spacing: 26) {
                    controlButton(icon: muted ? "mic.slash.fill" : "mic.fill",
                                  label: "Stumm", active: muted) { muted.toggle() }
                    controlButton(icon: "speaker.wave.3.fill",
                                  label: "Lautspr.", active: speakerOn) { speakerOn.toggle() }
                    controlButton(icon: "video.fill",
                                  label: "Video", active: false) { }
                }

                Button {
                    endCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(Theme.badgeRed, in: Circle())
                }
                .padding(.bottom, 44)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            connected = true
            while !finished {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !finished { elapsed += 1 }
            }
        }
    }

    private func controlButton(icon: String, label: String,
                               active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(active ? .black : .white)
                    .frame(width: 58, height: 58)
                    .background(active ? Color.white : Color.clear, in: Circle())
                    .glassCircle()
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func endCall() {
        finished = true
        onEnd(elapsed)
        dismiss()
    }
}
