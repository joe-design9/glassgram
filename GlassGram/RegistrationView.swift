import SwiftUI

/// Registration + activation screens (v2.0.0). These replace the
/// old offline invite gate: the account is created on the fixed
/// backend (anonymous auth + profile row), and in the normal build
/// the invite code is redeemed SERVER-side. There is no server
/// field anywhere — the endpoint is compiled in (BackendConfig).
///
/// States (Store.accountPhase):
///   .needsRegistration → RegistrationView (this file)
///   .needsCode         → CodeEntryView (returning, unactivated)
///   .waitingAdmin      → AdminWaitingView (admin build, unactivated)

// MARK: - Shared building blocks

private struct GateField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var codeStyle: Bool = false
    var usernameStyle: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .foregroundStyle(.white)
                .font(.system(size: 16, design: codeStyle ? .monospaced : .default))
                .textInputAutocapitalization(
                    codeStyle || usernameStyle ? .never : .words
                )
                .autocorrectionDisabled(codeStyle || usernameStyle)
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct GateHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 92, height: 92)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(18))
            }
            .glassCircle(interactive: false)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct GatePrimaryButton: View {
    let title: String
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .glassEffect(.regular.tint(Theme.accent.opacity(0.75)).interactive(), in: .capsule)
        .disabled(busy)
    }
}

// MARK: - Registration form

struct RegistrationView: View {
    @EnvironmentObject private var store: Store
    @State private var displayName: String = BuildVariant.isAdmin ? "Joel" : ""
    @State private var username: String = BuildVariant.isAdmin ? "joel" : ""
    @State private var code: String = ""
    @State private var error: String?
    @State private var busy = false

    private var isAdmin: Bool { BuildVariant.isAdmin }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)

                GateHeader(
                    title: "Willkommen bei GlassGram",
                    subtitle: isAdmin
                        ? "Admin-Version: Richte dein Besitzer-Konto ein — ganz ohne Code."
                        : "Der Messenger im Liquid-Glass-Design.\nDu brauchst einen Einladungscode, um reinzukommen."
                )

                VStack(spacing: 14) {
                    GateField(icon: "person.fill", placeholder: "Anzeigename", text: $displayName)
                    GateField(icon: "at", placeholder: "Benutzername (z. B. max.mustermann)",
                              text: $username, usernameStyle: true)
                    if !isAdmin {
                        GateField(icon: "key.fill", placeholder: "Einladungscode · GG-______-______",
                                  text: $code, codeStyle: true)
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.badgeRed)
                            .multilineTextAlignment(.center)
                    }

                    GatePrimaryButton(title: isAdmin ? "Konto einrichten" : "Los geht's", busy: busy) {
                        submit()
                    }
                }
                .padding(20)
                .glassCard()

                if !store.connectionOnline {
                    Text("Keine Verbindung zum Server — Registrierung braucht kurz Internet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.badgeRed)
                        .multilineTextAlignment(.center)
                }

                Text(isAdmin
                        ? "Dein Zugang wird nach der Einrichtung von Mochi freigeschaltet."
                        : "Der Code wird einmalig auf dem Server geprüft — danach bist du drin.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            let result = await store.register(displayName: displayName,
                                              username: username,
                                              code: code)
            busy = false
            if let result {
                error = result
            }
        }
    }
}

// MARK: - Code entry (returning, not yet activated — normal build)

struct CodeEntryView: View {
    @EnvironmentObject private var store: Store
    @State private var code: String = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)

                GateHeader(
                    title: "Fast geschafft",
                    subtitle: "Dein Konto existiert schon — es fehlt nur noch ein gültiger Einladungscode."
                )

                VStack(spacing: 14) {
                    GateField(icon: "key.fill", placeholder: "Einladungscode · GG-______-______",
                              text: $code, codeStyle: true)

                    if let error {
                        Text(error)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.badgeRed)
                            .multilineTextAlignment(.center)
                    }

                    GatePrimaryButton(title: "Code einlösen", busy: busy) {
                        busy = true
                        error = nil
                        Task {
                            let result = await store.submitCode(code)
                            busy = false
                            if let result {
                                error = result
                            }
                        }
                    }
                }
                .padding(20)
                .glassCard()

                if let profile = store.myProfile {
                    Text("Angemeldet als \(profile.displayName) (@\(profile.username))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }
}

// MARK: - Admin waiting screen

struct AdminWaitingView: View {
    @EnvironmentObject private var store: Store
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)

                GateHeader(
                    title: "Admin-Zugang",
                    subtitle: "Dein Admin-Zugang wird von Mochi freigeschaltet — sag kurz Bescheid, wenn du dich registriert hast."
                )

                VStack(spacing: 14) {
                    if let profile = store.myProfile {
                        VStack(spacing: 4) {
                            Text(profile.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("@\(profile.username)")
                                .font(.system(size: 14.5))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    GatePrimaryButton(title: "Status prüfen", busy: busy) {
                        busy = true
                        Task {
                            await store.refreshMyStatus()
                            busy = false
                        }
                    }
                }
                .padding(20)
                .glassCard()

                Text("Sobald die Freischaltung da ist, kommst du mit „Status prüfen“ direkt in die App und kannst Invite-Codes erstellen.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }
}
