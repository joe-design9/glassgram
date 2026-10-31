import SwiftUI
import UIKit

/// The conversation screen: Telegram-style bubbles over the
/// monochrome depth backdrop. Since v2.0.0 the header and the
/// input bar FLOAT as glass over the message scroll view — bubbles
/// pass beneath them and refract in the glass (real Liquid Glass
/// needs content behind the surface; stacked bars over flat black
/// read as matte shapes).
/// Keyboard: interactive scroll-dismiss + tap-outside guard — and
/// the field deliberately re-focuses after sending so chatting
/// can go on.
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

    private var isServerChat: Bool { store.isServerChat(chat.id) }

    private var statusText: String {
        if chat.isSavedMessages { return "Nachrichten an dich selbst" }
        return contact?.status ?? ""
    }

    var body: some View {
        ZStack {
            messageList

            // Floating glass header.
            VStack(spacing: 0) {
                header
                Spacer()
            }

            // Floating glass input bar (tray rides above it).
            VStack(spacing: 8) {
                Spacer()
                if showAttachTray { attachTray }
                inputBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .dismissKeyboardOnTap()
        .onAppear {
            store.openChatID = chat.id
            store.markRead(chatID: chat.id)
            if isServerChat {
                Task { await store.refreshConversation(chatID: chat.id) }
            }
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

    // MARK: Header (floating glass capsule)

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
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
            .glassPill()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: Messages (full-frame — they scroll UNDER the glass)

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
                // Clearance for the floating header / input bar —
                // layout insets only; the scroll region itself is
                // full-frame, so bubbles pass beneath the glass.
                .padding(.top, 66)
                .padding(.bottom, 84)
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

    // MARK: Attachment tray (Gespeichertes only — local demo actions
    // must never inject fake content into a real server chat)

    private var attachTray: some View {
        HStack(spacing: 12) {
            attachButton(icon: "photo.fill", label: "Foto", text: "Foto-Anhang (Demo)")
            attachButton(icon: "camera.fill", label: "Kamera", text: "Kamera-Foto (Demo)")
            attachButton(icon: "doc.fill", label: "Datei", text: "Datei-Anhang (Demo)")
        }
        .padding(.horizontal, 16)
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

    // MARK: Input bar (floating, grouped glass)

    private var inputBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                if chat.isSavedMessages {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showAttachTray.toggle() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .glassCircle()
                }

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Nachricht", text: $draft, axis: .vertical)
                        .foregroundStyle(.white)
                        .font(.system(size: 16.5 * store.settings.fontScale))
                        .lineLimit(1...5)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { send() }
                    if chat.isSavedMessages,
                       draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func send() {
        let text = draft
        draft = ""
        // Store routes: server chats → optimistic + POST,
        // "Gespeichertes" → purely local.
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
                message.isMine
                    ? .clear.tint(Theme.accent.opacity(0.55))
                    : .clear,
                in: .rect(cornerRadius: 18)
            )
            .specularEdge(RoundedRectangle(cornerRadius: 18))
            if !message.isMine { Spacer(minLength: 56) }
        }
    }
}
