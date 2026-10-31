# GlassGram

Ein Telegram-artiger Messenger im **Liquid-Glass-Design**: rein schwarze
Oberfläche, echtes `.glassEffect` überall (keine Material-Fallbacks),
Telegram-Blau als Akzent, schwebende Glas-Tab-Bar. Tabs: **Chats ·
Kontakte · Anrufe · Einstellungen**.

v1 läuft **komplett lokal** auf dem iPhone und startet **leer wie ein
echter Messenger** — keine Demo-Chats, keine Fake-Kontakte; Kontakte
legt der Nutzer selbst an. Anrufe sind eine lokale Demo ohne echte
Telefonie. Alle Daten liegen als JSON in UserDefaults.

## Zwei Versionen — ein Code

| Variante | Scheme | Konfiguration | IPA |
|---|---|---|---|
| Normal | `GlassGram` | `Release` | `GlassGram.ipa` |
| Admin | `GlassGramAdmin` | `ReleaseAdmin` (setzt `ADMIN_BUILD`) | `GlassGram-Admin.ipa` |

Es sind zwei echte, getrennt installierbare Apps: Normal =
`dev.joe.glassgram`, Admin = `dev.joe.glassgram.admin` (Anzeige:
„GlassGram Admin"). Die Admin-Version kennt **keine Code-Sperre**
(der Besitzer kommt direkt hinein) und enthält zusätzlich in den
Einstellungen den Bereich **„Admin · Invite-Codes"**.

## Einladungscodes (offline)

Vor der ersten Nutzung fragt die App **Anzeigename + Einladungscode**.
Geprüft wird offline über ein gemeinsames Verfahren
(`GlassGram/InviteCode.swift`), das beide Builds teilen — ein Code
aus der Admin-App funktioniert garantiert in der Normal-Version.

- **Format:** `GG-XXXXXX-XXXXXX`
  (Gruppe 1 = Payload-Zeichen 1–6, Gruppe 2 = Payload 7–10 + 2 Prüfzeichen)
- **Alphabet (30 Zeichen, ohne Verwechsler wie 0/1/I/L/O/U):**
  `23456789ABCDEFGHJKMNPQRSTVWXYZ`
- **Prüfsumme:** FNV-1a (32-bit) über `Salt + Payload`,
  Prüfzeichen 1 = `Alphabet[Hash % 30]`,
  Prüfzeichen 2 = `Alphabet[(Hash / 30) % 30]`.

Die Admin-Version startet mit **3 vorab erzeugten gültigen Codes**
(deterministisch aus festen Seeds, gleiches Verfahren), damit sofort
einer weitergegeben werden kann. Weitere Codes erzeugt der Admin in
der App (erstellen, kopieren, teilen, als „verteilt" markieren,
löschen).

## Kein Server-Feld — bewusst

Nutzer müssen **niemals** eine Server-Adresse eingeben. Es gibt
nirgendwo in der App ein URL-/Host-Feld (auch kein verstecktes).
Für den späteren Backend-Schritt ist der Endpunkt **eine einzige
fest einkompilierte Konstante** (`GlassGram/BackendConfig.swift` →
`BackendConfig.endpoint`) — nie nutzer-editierbar. Der Signup bleibt
immer: Anzeigename + Einladungscode, sonst nichts.

## Bauen

CI (`.github/workflows/build.yml`) baut bei jedem Release **beide**
Schemes ohne Signatur und hängt beide IPAs ans Release an:
`GlassGram.ipa` und `GlassGram-Admin.ipa`. Installation unsigned per
Sideloadly/AltStore.
