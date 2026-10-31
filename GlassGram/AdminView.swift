import SwiftUI
import UIKit

/// ADMIN BUILD ONLY — Invite-Code-Verwaltung (Server).
///
/// Since v2.0.0 the codes live on the backend (public.invite_codes):
/// creating inserts a row, redeeming marks it used_by server-side,
/// and this list is the server truth (refreshed on appear and after
/// every change). There is deliberately no delete/toggle here — a
/// code's state is whatever the server says it is.
struct AdminView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    @State private var copiedCode: String?
    @State private var createError: String?

    private struct ShareItem: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    Text("Codes werden auf dem Server erstellt und dort eingelöst — was hier steht, ist der echte Stand. Ein benutzter Code kann nicht noch einmal verwendet werden.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard()

                    Button {
                        Task {
                            createError = await store.createServerCode()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.adminBusy {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "plus.circle.fill")
                            }
                            Text("Code erstellen")
                        }
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                    }
                    .glassEffect(.clear.tint(Theme.accent.opacity(0.65)).interactive(), in: .capsule)
                    .disabled(store.adminBusy)

                    if let createError {
                        Text(createError)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.badgeRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if store.serverCodes.isEmpty {
                        Text("Noch keine Codes auf dem Server. Erstelle den ersten mit dem Button oben.")
                            .font(.system(size: 14.5))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 10)
                    } else {
                        ForEach(store.serverCodes) { entry in
                            codeCard(entry)
                        }
                    }

                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.refreshAdminCodes()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.text])
                .presentationBackground(.black)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 38)
            }
            Spacer()
            Text("Admin · Invite-Codes")
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button {
                Task { await store.refreshAdminCodes() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 38)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func codeCard(_ entry: GGInviteCodeRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(entry.code)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                statusChip(entry)
            }

            Text("Erstellt am \(TimeFormat.dateOnly(entry.createdAt))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)

            if let usedBy = entry.usedBy {
                Text("Eingelöst von \(store.codeUsedByNames[usedBy] ?? "einem Nutzer")")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                smallButton(icon: "doc.on.doc", label: copiedCode == entry.code ? "Kopiert!" : "Kopieren") {
                    UIPasteboard.general.string = entry.code
                    copiedCode = entry.code
                }
                smallButton(icon: "square.and.arrow.up", label: "Teilen") {
                    shareItem = ShareItem(
                        text: "Dein GlassGram-Einladungscode: \(entry.code) — einfach bei der Registrierung in der App eingeben."
                    )
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private func statusChip(_ entry: GGInviteCodeRow) -> some View {
        Text(entry.isUsed ? "benutzt" : "frei")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(entry.isUsed
                                ? Theme.secondaryText
                                : Color(red: 0.35, green: 0.85, blue: 0.45))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                (entry.isUsed
                    ? Color.white
                    : Color(red: 0.35, green: 0.85, blue: 0.45)).opacity(0.14),
                in: Capsule()
            )
    }

    private func smallButton(icon: String, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassPill(interactive: true)
    }
}
