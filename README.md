# GlassGram

Ein Telegram-artiger Messenger im **Liquid-Glass-Design**: schwarze
Oberfläche mit dezentem Tiefen-Hintergrund (monochrom), echtes
`.glassEffect` überall (keine Material-Fallbacks), Telegram-Blau als
Akzent, schwebende Glas-Tab-Bar, die über dem scrollenden Inhalt
liegt. Tabs: **Chats · Kontakte · Anrufe · Einstellungen**.

Seit **v2.0.0** ist GlassGram ein echter Client für das fest
eingebaute Supabase-Backend: Konten (anonyme Anmeldung + Profil),
1:1-Chats, Kontaktsuche per Benutzername und Invite-Codes laufen
über den Server, Aktualisierung per Polling (Chatliste ~5 s,
offener Chat ~2 s). **„Gespeichertes“ bleibt rein lokal** und
verlässt das Gerät nie; auch die Anrufliste ist lokal (Anrufe sind
eine In-App-Simulation ohne echte Telefonie und ohne Server).

## Zwei Versionen — ein Code

| Variante | Scheme | Konfiguration | IPA |
|---|---|---|---|
| Normal | `GlassGram` | `Release` | `GlassGram.ipa` |
| Admin | `GlassGramAdmin` | `ReleaseAdmin` (setzt `ADMIN_BUILD`) | `GlassGram-Admin.ipa` |
| QA (nur Simulator-Screenshots, nie Release) | `GlassGram` | `QA` (Klon von Debug, setzt `QA`) | — |

Es sind zwei echte, getrennt installierbare Apps: Normal =
`dev.joe.glassgram`, Admin = `dev.joe.glassgram.admin` (Anzeige:
„GlassGram Admin“).

## Registrierung & Einladungscodes (Server)

- **Normal:** Anzeigename + Benutzername + Invite-Code →
  anonyme Anmeldung → Profil anlegen → Code per RPC einlösen.
  Ungültiger/benutzter Code = klare Fehlermeldung, der Code kann
  danach erneut eingegeben werden.
- **Admin:** nur Anzeigename + Benutzername (Formular mit
  „joel“/„Joel“ vorbefüllt). Danach Wartestatus, bis das Konto
  serverseitig als Admin freigeschaltet wird.
- **Admin-Bereich** (Einstellungen → „Admin · Invite-Codes“, nur
  Admin-Build + Admin-Konto): Codes werden **auf dem Server**
  erstellt und dort eingelöst — die Liste zeigt den echten Stand
  (frei / benutzt + von wem). Format `GG-XXXXXX-XXXXXX` mit
  FNV-1a-Prüfsumme (`GlassGram/InviteCode.swift`); die App prüft
  das Format lokal vor, die Wahrheit liegt auf dem Server.

## Kein Server-Feld — bewusst

Nutzer geben **niemals** eine Server-Adresse ein. Es gibt
nirgendwo in der App ein URL-/Host-Feld (auch kein verstecktes).
Der Endpunkt ist **eine einzige fest einkompilierte Konstante**
(`GlassGram/BackendConfig.swift` → `BackendConfig.endpoint`,
dazu der öffentliche Anon-Key des Projekts — die Daten schützt
Row Level Security auf dem Server).

## QA-Screenshots (Liquid Glass visuell prüfen)

Siehe **QA.md**: Die `QA`-Konfiguration + Startargument
`-UITestMode` zeigt die echte Hauptoberfläche mit lokalen
Beispieldaten — ganz ohne Konto/Server —, damit die Glasflächen
(Tab-Bar, Header, Bubbles über scrollendem Inhalt) im Simulator
fotografiert und geprüft werden können, bevor irgendetwas
erscheint. In Release/ReleaseAdmin ist der Modus nicht
erreichbar (doppelt abgesichert: Compilation Condition + Argument).

## Bauen

CI (`.github/workflows/build.yml`) baut bei jedem Release **beide**
Schemes ohne Signatur und hängt beide IPAs ans Release an:
`GlassGram.ipa` und `GlassGram-Admin.ipa`. Installation unsigned per
Sideloadly/AltStore.
