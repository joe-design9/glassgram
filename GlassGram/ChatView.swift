import SwiftUI
import UIKit

/// The conversation screen: Telegram-style bubbles on black, glass
/// input bar.
/// Keyboard: interactive scroll-dismiss + tap-outside guard — and the
/// field deliberately re-focuses after sending so chatting can go on.
struct ChatView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let chat: GGChat

    @State private var draft = ""
    @State private var showAttachTray = false
    @State private var callContact: GGContact?
    @FocusState private var inputFocused: Bool

    private var contact: GGContact? {
        chat.contactID.flatMap { store.contact(id: $0) }
    }

    private var statusText: String {
        if chat.isSavedMessages { return "Nachrichten an dich selbst" }
        return contact?.status ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.10))
            messageList
            if showAttachTray { attachTray }
            inputBar
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .dismissKeyboardOnTap()
        .onAppear {
            store.openChatID = chat.id
            store.markRead(chatID: chat.id)
        }
        .onDisappear {
            if store.openChatID == chat.id { store.openChatID = nil }
        }
        .fullScreenCover(item: $callContact) { contact in
            CallScreen(contact: contact) { duration in
                store.logOutgoingCall(contactID: contact.id, durationSec: duration)
                callContact = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 38)
            }

            if chat.isSavedMessages {
                SavedAvatarView(size: 38)
            } else {
                AvatarView(title: chat.title, colorIndex: chat.colorIndex, size: 38)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if let contact, !chat.isSavedMessages {
                Button {
                    callContact = contact
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                }
                .glassCircle()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.messages(for: chat.id)) { message in
                        MessageBubble(message: message, fontScale: store.settings.fontScale)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: store.messages(for: chat.id).count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: Attachment tray (demo, but functional)

    private var attachTray: some View {
        HStack(spacing: 12) {
            attachButton(icon: "photo.fill", label: "Foto", text: "Foto-Anhang (Demo)")
            attachButton(icon: "camera.fill", label: "Kamera", text: "Kamera-Foto (Demo)")
            attachButton(icon: "doc.fill", label: "Datei", text: "Datei-Anhang (Demo)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func attachButton(icon: String, label: String, text: String) -> some View {
        Button {
            showAttachTray = false
            store.sendMessage(chatID: chat.id, text: text)
            inputFocused = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassCard(cornerRadius: 18)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showAttachTray.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassCircle()

            HStack(alignment: .bottom, spacing: 6) {
                TextField("Nachricht", text: $draft, axis: .vertical)
                    .foregroundStyle(.white)
                    .font(.system(size: 16.5 * store.settings.fontScale))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        store.sendMessage(chatID: chat.id, text: "Sprachnachricht · 0:12 (Demo)")
                        inputFocused = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassPill()

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: Circle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func send() {
        let text = draft
        draft = ""
        store.sendMessage(chatID: chat.id, text: text)
        if store.settings.vibrationEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        inputFocused = true
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: GGMessage
    let fontScale: Double

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 56) }
            HStack(alignment: .bottom, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 16.5 * fontScale))
                    .foregroundStyle(.white)
                HStack(spacing: 2) {
                    Text(TimeFormat.bubble(message.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.65))
                    if message.isMine {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.bottom, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(
                .regular.tint(message.isMine
                                ? Theme.accent.opacity(0.48)
                                : .white.opacity(0.13)),
                in: .rect(cornerRadius: 18)
            )
            .specularEdge(RoundedRectangle(cornerRadius: 18))
            if !message.isMine { Spacer(minLength: 56) }
        }
    }
}
