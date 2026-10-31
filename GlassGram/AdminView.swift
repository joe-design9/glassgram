import SwiftUI
import UIKit

/// ADMIN BUILD ONLY — Invite-Code-Verwaltung.
/// Codes are generated with the shared offline algorithm
/// (InviteCode.swift), so every code created here validates in the
/// normal build's welcome gate. Codes live only on this device.
struct AdminView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    @State private var copiedID: UUID?

    private struct ShareItem: Identifiable {
        let id = UUID()
        let text: String
        let codeID: UUID
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    Text("Codes funktionieren offline in der normalen GlassGram-Version — die App prüft nur die eingebaute Prüfsumme. Kein Server nötig.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard()

                    Button {
                        store.createAdminCode()
                    } label: {
                        Label("Code erstellen", systemImage: "plus.circle.fill")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.75)).interactive(), in: .capsule)

                    if store.adminCodes.isEmpty {
                        Text("Noch keine Codes. Erstelle den ersten mit dem Button oben.")
                            .font(.system(size: 14.5))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 10)
                    } else {
                        ForEach(store.adminCodes) { entry in
                            codeCard(entry)
                        }
                    }

                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.text])
                .presentationBackground(.black)
                .onDisappear {
                    // A completed share counts as handed out.
                    store.markAdminCodeShared(id: item.codeID)
                }
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
            Color.clear.frame(width: 34, height: 38)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private func codeCard(_ entry: AdminCode) -> some View {
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

            HStack(spacing: 10) {
                smallButton(icon: "doc.on.doc", label: copiedID == entry.id ? "Kopiert!" : "Kopieren") {
                    UIPasteboard.general.string = entry.code
                    copiedID = entry.id
                    store.markAdminCodeShared(id: entry.id)
                }
                smallButton(icon: "square.and.arrow.up", label: "Teilen") {
                    shareItem = ShareItem(
                        text: "Dein GlassGram-Einladungscode: \(entry.code) — einfach beim Start in der App eingeben.",
                        codeID: entry.id
                    )
                }
                smallButton(icon: entry.status == "frei" ? "checkmark.circle" : "arrow.uturn.backward.circle",
                            label: entry.status == "frei" ? "Verteilt" : "Frei") {
                    store.toggleAdminCodeStatus(id: entry.id)
                }
                smallButton(icon: "trash", label: "Löschen", danger: true) {
                    store.deleteAdminCode(id: entry.id)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private func statusChip(_ entry: AdminCode) -> some View {
        Text(entry.status == "frei" ? "frei" : "verteilt")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(entry.status == "frei"
                                ? Color(red: 0.35, green: 0.85, blue: 0.45)
                                : Theme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                (entry.status == "frei"
                    ? Color(red: 0.35, green: 0.85, blue: 0.45)
                    : Color.white).opacity(0.14),
                in: Capsule()
            )
    }

    private func smallButton(icon: String, label: String,
                             danger: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(danger ? Theme.badgeRed : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassPill(interactive: true)
    }
}
