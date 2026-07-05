# Blur Wallpaper Maker

Kleine native macOS-App (SwiftUI). Nimmt ein Unsplash-Foto (oder ein eigenes Bild)
als Quelle und macht daraus per Gaussian-Blur ein weiches Gradient-Wallpaper in
Display-Auflösung — Export per **Drag & Drop** oder Speichern-Dialog.

## Bauen & starten

```bash
cp .env.example .env          # einmalig: Unsplash-Key eintragen
./build.sh
open "build/Blur Wallpaper Maker.app"
```

Benötigt nur die **Command Line Tools** (`xcode-select --install`), kein volles Xcode.
Gebaut für Apple Silicon / macOS 14+.

## Unsplash Access-Key

Der Key liegt in einer **gitignorten `.env`** und wird beim Bauen in
`build/Secrets.generated.swift` injiziert (nichts davon landet im Repo):

```
UNSPLASH_ACCESS_KEY=dein_key
```

Kostenlos erstellbar unter https://unsplash.com/developers → **New Application**
(der **Access Key**, nicht der Secret Key). Alternativ lässt sich in der App unter
**⌘,** (Einstellungen) ein Key eintragen, der den aus `.env` überschreibt.

Ohne Key funktioniert **„Eigenes Bild öffnen…"** weiterhin mit jeder lokalen
Bilddatei.

## Bedienung

- Links: Foto suchen & anklicken, oder eigenes Bild öffnen.
- Rechts: Auflösung wählen (Standard **Pro Display XDR — 6016 × 3384**) und die
  Regler **Blur / Helligkeit / Sättigung / Kontrast** anpassen.

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
  App.swift            App-Einstieg + Settings-Szene
  ContentView.swift    UI (Sidebar, Vorschau, Regler, Settings)
  Model.swift          Zustand, Looks (Hell/Dunkel), Export/Drag/Desktop
  Unsplash.swift       Unsplash-API-Client
  BlurProcessor.swift  Core-Image-Blur/Gradient-Pipeline
  DynamicWallpaper.swift  HEIC-Writer mit Light/Dark-Metadaten
Info.plist             Bundle-Metadaten
build.sh               swiftc → .app-Bundle
```

## Hinweis Unsplash

Fotos stammen von Unsplash. Die App zeigt den Fotografen an und meldet Downloads
gemäß der Unsplash-API-Richtlinien. Für eine öffentliche Verteilung braucht Unsplash
eine Freigabe („production"-Status) der API-Anwendung.
