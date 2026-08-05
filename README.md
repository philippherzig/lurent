# Lurent

Native macOS-App (SwiftUI). Lurent macht aus einem Foto ein weiches, abstraktes
Wallpaper: Bild wählen, mit den Effektreglern formen — Blur, Spiegel, Lamellen,
Liquid —, als Schreibtischhintergrund setzen. Gerendert wird ein quadratisches
6016²-Master, das auf jedem Mac-Display bis zum Pro Display XDR in nativer Auflösung
landet. Jedes Wallpaper bleibt als `.lurent`-Projekt erhalten.

## Bauen & starten

```bash
cp .env.example .env          # einmalig: Unsplash-Key eintragen
./build.sh
open "build/Lurent.app"
```

Benötigt nur die **Command Line Tools** (`xcode-select --install`), kein volles Xcode.
Gebaut für Apple Silicon / macOS 26+ (`LSMinimumSystemVersion` 26.0).

## Signieren & Notarisieren

`build.sh` erkennt automatisch eine **„Developer ID Application"**-Identität in
deinem Schlüsselbund und signiert damit inkl. **Hardened Runtime**, den
Entitlements aus `Lurent.entitlements` und einem sicheren Zeitstempel. Ohne
Developer-ID-Zertifikat fällt es auf **Ad-hoc**-Signatur zurück (läuft lokal,
wird aber nach dem Download von Gatekeeper abgelehnt). Ist der Apple-Zeitstempel-
Server nicht erreichbar (offline), signiert es ohne Zeitstempel weiter — das
Ergebnis läuft lokal, muss für die Notarisierung aber online neu gebaut werden.

```bash
./build.sh                                   # auto-erkennt Developer ID
SIGN_IDENTITY="Developer ID Application: …" ./build.sh   # Identität erzwingen
SIGN_IDENTITY="-" ./build.sh                 # Ad-hoc erzwingen (nur lokal)
```

Für die Verteilung an andere Macs muss die App zusätzlich **notarisiert** werden.
Einmalig die Apple-Credentials im Schlüsselbund hinterlegen (App-spezifisches
Passwort von https://account.apple.com → *Anmelden & Sicherheit*):

```bash
xcrun notarytool store-credentials "lurent-notary" \
  --apple-id "du@example.com" --team-id "6UQUNT93NG" --password "xxxx-xxxx-xxxx-xxxx"
```

Danach genügt nach jedem signierten Build:

```bash
./notarize.sh          # zippt, reicht ein, wartet, stapelt das Ticket & prüft
```

### Verteilung

Eine notarisierte `.app` läuft **von überall** (Download-Ordner, Desktop, USB) —
ein Installer ist optional. Für ein Doppelklick-Setup, das die App nach
`/Applications` legt, baut `package.sh` ein signiertes + notarisiertes `.pkg`
(nutzt das „Developer ID Installer"-Zertifikat und dasselbe `lurent-notary`-
Profil). Es notarisiert + stapelt dabei zuerst die App selbst (falls noch nicht
geschehen), damit die installierte App auch offline von Gatekeeper akzeptiert
wird:

```bash
./build.sh && ./package.sh    # → build/Lurent.pkg (notarisiert notfalls auch die App)
```

## Website (lurent.app)

Die Seite liegt in `site/` und läuft auf **Cloudflare Pages**, Projekt `lurent`.
Das Projekt hängt am GitHub-Repo: **ein Merge nach `main` deployt sie**, es gibt
kein Skript und keinen manuellen Upload.

| Einstellung | Wert |
|---|---|
| Build command | *(leer — reines HTML, kein Build)* |
| Build output directory | `site` |
| Production branch | `main` |

Zwei Eigenheiten von Pages, die beim Prüfen täuschen:

- **Keine 404-Seite.** Jeder Pfad antwortet mit HTTP 200 und der Startseite. Ein
  `curl -I` auf `/privacy` sieht also auch dann gut aus, wenn die Seite fehlt —
  immer den Inhalt prüfen, nicht den Statuscode.
- **Clean URLs.** `/privacy.html` wird per **308** auf `/privacy` umgeleitet;
  Prüfungen müssen der Weiterleitung folgen.

Dazu hinkt der Edge-Cache nach einem Deploy rund eine Minute nach. Wenn die alte
Fassung erscheint: kurz warten, bevor du suchst.

`privacy.html` und `support.html` sind Pflichtfelder im App Store und müssen
echten Inhalt liefern.

## Unsplash Access-Key

Der Key liegt in einer **gitignorten `.env`** und wird beim Bauen in
`build/Secrets.generated.swift` injiziert (nichts davon landet im Repo):

```
UNSPLASH_ACCESS_KEY=dein_key
```

Kostenlos erstellbar unter https://unsplash.com/developers → **New Application**
(der **Access Key**, nicht der Secret Key). Dieser gebackene Key ist der einzige,
den die App verwendet — Endnutzer müssen (und können) keinen eigenen eintragen.

Ohne Key funktioniert **„Eigenes Bild öffnen…"** weiterhin mit jeder lokalen
Bilddatei.

## Bedienung

- Links: Foto suchen & anklicken, oder eigenes Bild öffnen.
- Rechts: **Stil** wählen (Blur / Flow), Auflösung (Standard
  **Pro Display XDR — 6016 × 3384**) und die zugehörigen Regler anpassen.

### Stile: Blur & Flow

- **Blur** — weiches Gradient-Wallpaper aus dem Foto. Regler:
  Blur / Helligkeit / Sättigung / Kontrast.
- **Flow** — fließende Farbbänder mit einer harten Kante entlang einer
  Sinuslinie, die nur zu den Rändern weich zerläuft (Icon-Composer-Look). Die
  2–3 Farben werden aus dem Foto extrahiert (per Color-Picker überschreibbar,
  „Aus Foto" lädt neu). Regler: Amplitude / Frequenz / Kantenschärfe /
  Rand-Weichheit / Variante. Funktioniert auch ohne Foto (Default-Palette).
- **Spiegel** — faltet den unteren Teil des geblurrten Fotos entlang einer
  geschwungenen Linie in sich selbst (keine Motiv-Dopplung), mit optional
  100 % harter Kante, die zu den Rändern ausblendet — ergibt Berg-/Horizont-
  Silhouetten. Regler: Blur / Spiegel-Linie / Amplitude / Frequenz /
  Kantenschärfe / Tiefe / Seiten-Fade.

Beide Stile teilen den 16-Bit/Dither-Ausgabepfad und lassen sich statisch oder
dynamisch (Hell/Dunkel) exportieren. Der Regler **Körnung** fügt optionales
Filmkorn hinzu (Standard dezent — Banding wird bereits durch die 16-Bit-Ausgabe
vermieden).

### Statisch vs. Hell + Dunkel

Oben im Editor umschaltbar:

- **Statisch** — ein Wallpaper, Export als PNG.
- **Hell + Dunkel** — pro Appearance ein eigenes Bild + eigene Regler.
  „Quelle für … übernehmen" kopiert das Bild in die andere Appearance. Export
  als **dynamisches `.heic`**, das macOS je nach Erscheinungsbild automatisch
  umschaltet.

### Export

- **Drag & Drop:** die Vorschau in den Finder / auf den Schreibtisch ziehen
  (rendert on-the-fly in voller Auflösung; im Dynamik-Modus das HEIC).
- **Exportieren… (⌘S):** Speichern-Dialog. Dateiname kommt vom Unsplash-Slug
  bzw. vom Original-Dateinamen.
- **Als Schreibtisch setzen:** setzt das Ergebnis direkt als Hintergrund auf
  allen Bildschirmen. Schaltet der Button das Dynamik-Wallpaper nicht um, das
  HEIC exportieren und einmal in *Systemeinstellungen › Hintergrundbild*
  auswählen — dort greift die Appearance-Automatik zuverlässig.

### Bild­qualität (Anti-Banding)

Stark geblurrte Verläufe zeigen auf 10-Bit-Displays wie dem Pro Display XDR
leicht sichtbare Streifen (Color Banding). Dagegen:

- **16-Bit-PNG** beim statischen Export, **10-Bit-HEIC** beim Dynamik-Export.
- **Dithering** (Regler „Körnung") bricht die Bänder auf; Standard ist ein
  dezenter Wert, höher = mehr Körnung.

### Dynamisches HEIC-Format

macOS 26 (Tahoe) erkennt Hell/Dunkel-Wallpaper am Metadaten-Tag
`apple_desktop:apr` mit flachem `{ l, d }` — identisch zu den System-Wallpapern
(`/System/Library/Desktop Pictures/Sonoma.heic`). Genau dieses Tag schreibt die
App (plus das ältere `apple_desktop`-Format für frühere macOS-Versionen).

## Auflösungen

| Preset | Pixel |
|---|---|
| Pro Display XDR | 6016 × 3384 |
| Studio Display 5K | 5120 × 2880 |
| iMac 24" 4.5K | 4480 × 2520 |
| MacBook Pro 16" | 3456 × 2234 |
| MacBook Pro 14" | 3024 × 1964 |
| MacBook Air 13" | 2560 × 1664 |
| 4K UHD | 3840 × 2160 |
| Full HD | 1920 × 1080 |
| Eigene Größe | frei |

## Aufbau

```
Sources/
  App.swift            App-Einstieg + Settings-Szene + Update-Menüpunkt
  ContentView.swift    UI (Sidebar, Vorschau, Regler, Settings)
  Model.swift          Zustand, Looks (Hell/Dunkel), Export/Drag/Desktop
  Updater.swift        Leerer Platzhalter — Updates kommen aus dem App Store
  Unsplash.swift       Unsplash-API-Client
  BlurProcessor.swift  Core-Image-Blur/Gradient-Pipeline
  DynamicWallpaper.swift  HEIC-Writer mit Light/Dark-Metadaten
Info.plist             Bundle-Metadaten (+ .lurent-Dokumenttyp)
Lurent.entitlements    Hardened-Runtime-Entitlements (Photos-Zugriff)
build.sh               swiftc → .app-Bundle (signiert; PROVISION_PROFILE=… → App-Store-Variante)
notarize.sh            Notarisieren & Ticket stapeln für die Verteilung
package.sh             Signiertes + notarisiertes .pkg für /Applications
Tools/provision-r2.sh   Einmaliges R2-Setup (Bucket + Custom Domain)
```

## Hinweis Unsplash

Fotos stammen von Unsplash. Die App zeigt den Fotografen an und meldet Downloads
gemäß der Unsplash-API-Richtlinien. Für eine öffentliche Verteilung braucht Unsplash
eine Freigabe („production"-Status) der API-Anwendung.
