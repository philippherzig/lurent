#!/bin/bash
# Publishes a release on GitHub: zips the notarized Lurent.app, EdDSA-signs the
# archive for Sparkle (key from the login Keychain), writes an appcast.xml for it,
# and creates the GitHub release `v<version>` carrying both files.
#
# Every release ships its own appcast, so `releases/latest/download/appcast.xml`
# (SUFeedURL) and `releases/latest/download/Lurent.zip` (the download button)
# always point at the newest version. Bump CFBundleShortVersionString and
# CFBundleVersion in Info.plist first: Sparkle compares CFBundleVersion.
#
# Prereqs: ./build.sh with a Developer ID, the `lurent-notary` profile, `gh` logged in.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lurent.app"
SPARKLE_BIN="$ROOT/vendor/Sparkle/bin"
OUT="$ROOT/build/release"
REPO="philippherzig/lurent"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first." >&2; exit 1; }
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "✗ Sparkle tools missing — run ./Tools/fetch-sparkle.sh" >&2; exit 1; }

# Capture first, then grep: `codesign | grep -q` can SIGPIPE-fail under pipefail.
SIG_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
grep -q "Authority=Developer ID Application" <<<"$SIG_INFO" \
  || { echo "✗ $APP is not Developer-ID signed — run ./build.sh with a Developer ID." >&2; exit 1; }
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "▸ App already notarized & stapled"
else
  echo "▸ Notarizing first"
  bash "$ROOT/notarize.sh"
fi

PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
TAG="v$VERSION"
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "✗ Release $TAG already exists — bump the version in Info.plist." >&2; exit 1
fi

echo "▸ Archiving Lurent.app ($VERSION build $BUILD)"
rm -rf "$OUT"; mkdir -p "$OUT"
ZIP="$OUT/Lurent.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "▸ Signing the archive for Sparkle (may ask once for Keychain access)"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Lurent</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/Lurent.zip" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

echo "▸ Creating GitHub release $TAG"
NOTES_ARGS=(--generate-notes)
[ -n "${NOTES_FILE:-}" ] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" -R "$REPO" \
  --target main --title "Lurent $VERSION" "${NOTES_ARGS[@]}"

echo "✓ Published $VERSION (build $BUILD)"
echo "  https://github.com/$REPO/releases/tag/$TAG"
