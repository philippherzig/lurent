# Lurent

Lurent is a native macOS app that turns a photo into a soft, abstract wallpaper.
Pick a picture, shape it with the effect controls, and set it as your desktop.

- **Styles:** Blur, Mirror, Slats and Liquid. Liquid needs no photo at all.
- **Light and dark:** each wallpaper can have its own look per appearance and
  exports as a dynamic HEIC that macOS switches automatically.
- **Any display:** renders a square 6016 × 6016 master that fills every Mac
  display at full resolution, landscape or portrait.
- **Projects:** every wallpaper is kept as a `.lurent` document in
  `iCloud Drive/Lurent/`, so it can be reopened and changed later.
- **Photo sources:** Wikimedia Commons, Pexels, Unsplash, your Photos library,
  or any image file.

Requires macOS 26 or later on Apple Silicon.

## Build

```bash
./build.sh
open build/Lurent.app
```

Only the Command Line Tools are needed (`xcode-select --install`), not Xcode.
Without a Developer ID certificate in your keychain the build is signed ad hoc,
which runs fine on your own Mac.

## API keys

Commons needs no key. For the others, open **Lurent › Settings…**:

- **Pexels** works without a key through a shared cache at `pexels.lurent.app`.
  A free key of your own from [pexels.com/api](https://www.pexels.com/api/)
  sends searches straight to Pexels on your own quota.
- **Unsplash** needs your own access key from
  [unsplash.com/developers](https://unsplash.com/developers). A demo app's key
  allows 50 searches an hour, which is plenty for personal use.

Keys are stored in your login keychain and never leave your Mac except to their
own service.

## Distributing a build

For others to run your build, sign it with a Developer ID and notarize it:

```bash
./build.sh                    # picks up a "Developer ID Application" identity
./notarize.sh                 # needs a notarytool keychain profile "lurent-notary"
./package.sh                  # optional: a notarized .pkg installer
```

Create the notary profile once with
`xcrun notarytool store-credentials lurent-notary --apple-id … --team-id … --password …`
(an app-specific password from account.apple.com).

## Layout

```
Sources/            The app (SwiftUI + Core Image)
Localizations/      UI strings; German is the base language, keys are the German text
workers/pexels-cache/  Cloudflare Worker behind pexels.lurent.app
site/               lurent.app, deployed by Cloudflare Pages on every merge to main
Tools/              Icon and contact-sheet helpers
```

## Photo credits

Every photo from an online source shows its photographer and a link to where it
lives. Commons photos are mostly CC BY-SA; the linked file page states the exact
licence. Unsplash and Pexels photos follow their own licences.

## License

MIT, see [LICENSE](LICENSE).
