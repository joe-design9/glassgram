# QA — Liquid-Glass-Screenshots (Simulator)

Zweck: Die Glasflächen von GlassGram (schwebende Tab-Bar, Header,
Eingabeleiste, Bubbles) werden **vor jedem Release visuell geprüft** —
echte Screenshots der echten UI über scrollendem Inhalt, statt blind
zu shippen. Dafür gibt es einen internen Testmodus, der **niemals**
in den Release-IPAs erreichbar ist.

## Wie der Modus abgesichert ist (doppelte Sperre)

1. **Build-Konfiguration `QA`** (Klon von `Debug`) setzt die
   Compilation Condition `QA` (Projekt- und Target-Ebene in
   `GlassGram.xcodeproj/project.pbxproj`). Release/ReleaseAdmin
   kompilieren die Bedingung nicht — der Codepfad existiert in den
   IPAs praktisch nicht.
2. **Startargument `-UITestMode`**: Nur wenn beides zusammenkommt
   (`Store.isUITestMode` in `GlassGram/Store.swift`), überspringt
   die App Registrierung/Auth komplett und startet direkt in der
   Hauptoberfläche mit **lokalen Beispieldaten** (5 Chats mit
   Nachrichtenverläufen, Gespeichertes-Notizen, ein Anruflisten-
   Eintrag, ein Ungelesen-Badge). Alle Netzwerkpfade sind in
   diesem Modus hart deaktiviert — es geht nichts an den Server.

Die Beispieldaten werden ausschließlich in
`Store.seedQASampleData()` erzeugt (nur unter `-UITestMode`).
Mit dem zusätzlichen Argument `-UITestScreen chat` bzw.
`-UITestScreen contacts` startet die App direkt im offenen
Beispiel-Chat bzw. im Kontakte-Tab — so kann die CI ohne Taps
jeden Bildschirm fotografieren.

## QA-Build erzeugen (iOS Simulator)

```sh
xcodebuild \
  -project GlassGram.xcodeproj \
  -scheme GlassGram \
  -configuration QA \
  -sdk iphonesimulator \
  -derivedDataPath "$PWD/build-qa" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

App-Bundle danach:
`build-qa/Build/Products/QA-iphonesimulator/GlassGram.app`

## Starten & fotografieren

```sh
# Simulator booten (Gerät nach Wahl), App installieren
xcrun simctl boot "iPhone 17 Pro Max"   # Beispiel
xcrun simctl install booted build-qa/Build/Products/QA-iphonesimulator/GlassGram.app

# Mit Testmodus starten (WICHTIG: das Argument muss mit)
xcrun simctl launch booted dev.joe.glassgram -UITestMode

# Screenshot
xcrun simctl io booted screenshot qa-chats.png
```

## Diese Screens aufnehmen (Prüfliste)

1. **Chats-Liste** — Tab-Bar + Header/Search-Glas über den
   Chat-Zeilen; einmal zusätzlich leicht gescrollt, damit Zeilen
   sichtbar **unter** der Tab-Bar / dem Header durchlaufen
   (Refraktion prüfen).
2. **Ein offener Chat** (z. B. „Lena Meyer“) — Bubbles über dem
   Tiefen-Hintergrund, Eingabeleiste als schwebendes Glas über
   den Nachrichten; ggf. gescrollt.
3. **Kontakte** — Partnerliste + Such-Glas.

Prüfmaßstab: Glas muss als Glas lesen (Blur/Refraktion des
Inhalts dahinter + spekulare Kante), nicht als matte graue Form.
Erst wenn die Screenshots das zeigen, darf ein Release gebaut
werden.
