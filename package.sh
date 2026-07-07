#!/bin/bash
# Builds a signed, notarized macOS installer (.pkg) that drops Lurent.app into
# /Applications. Requires a Developer-ID-signed build (./build.sh) and a
# "Developer ID Installer" identity in the keychain. Notarizes with the same
# "lurent-notary" keychain profile that notarize.sh uses.
#
# A .pkg is optional — a notarized .app runs from anywhere. Use this when you
# want a double-click installer that puts the app in /Applications for the user.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lurent.app"
PKG="$ROOT/build/Lurent.pkg"
PROFILE="${NOTARY_PROFILE:-lurent-notary}"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first." >&2; exit 1; }

# The app must be Developer-ID signed (the installer inherits its trust).
SIG_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
if ! grep -q "Authority=Developer ID Application" <<<"$SIG_INFO"; then
  echo "✗ $APP is not Developer-ID signed — run ./build.sh with a Developer ID first." >&2
  exit 1
fi

# Find the Developer ID Installer identity (INSTALL_IDENTITY overrides).
INSTALL_IDENTITY="${INSTALL_IDENTITY-auto}"
if [ "$INSTALL_IDENTITY" = "auto" ]; then
  INSTALL_IDENTITY="$(security find-identity -v \
    | awk -F'"' '/Developer ID Installer/ {print $2; exit}')"
fi
[ -n "$INSTALL_IDENTITY" ] || {
  echo "✗ No 'Developer ID Installer' identity found in the keychain." >&2
  echo "  (That's a separate cert from 'Developer ID Application'.)" >&2
  exit 1
}

# Notarize + staple the app *before* packaging it, so the installed copy carries
# its own ticket (stapling the .pkg does not staple its payload — an unstapled
# app can be blocked by Gatekeeper on an offline first launch). notarize.sh is a
# no-op-ish re-run only when the app isn't stapled yet; skip it if it already is.
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "▸ App already notarized & stapled"
else
  echo "▸ App not stapled yet — notarizing it first (via notarize.sh)"
  bash "$ROOT/notarize.sh"
fi

echo "▸ Staging app for a non-relocatable payload"
# Copy the app into a clean root so the payload is exactly Lurent.app (build/
# also holds other artifacts). ditto preserves the code signature & staple.
STAGE="$ROOT/build/pkgroot"
CPLIST="$ROOT/build/component.plist"
COMPONENT_PKG="$ROOT/build/Lurent-component.pkg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Lurent.app"

# Turn OFF bundle relocation. With the default (relocatable=true) the Installer
# follows an existing copy found by bundle id via Spotlight and installs the
# update on top of THAT (e.g. this build folder) instead of /Applications.
pkgbuild --analyze --root "$STAGE" "$CPLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$CPLIST"

echo "▸ Building signed installer → $PKG"
pkgbuild --root "$STAGE" --component-plist "$CPLIST" \
  --install-location /Applications "$COMPONENT_PKG"
productbuild --package "$COMPONENT_PKG" --sign "$INSTALL_IDENTITY" "$PKG"
rm -rf "$STAGE" "$CPLIST" "$COMPONENT_PKG"
echo "  ✓ signed: $INSTALL_IDENTITY (non-relocatable → always /Applications)"

echo "▸ Notarizing the installer (waits for the result)"
if ! xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait; then
  echo "✗ Installer notarization failed (see the error above)." >&2
  echo "  If it names a missing keychain profile \"$PROFILE\", create it once:" >&2
  echo "    xcrun notarytool store-credentials \"$PROFILE\" \\" >&2
  echo "      --apple-id \"you@example.com\" --team-id \"6UQUNT93NG\" --password \"xxxx-xxxx-xxxx-xxxx\"" >&2
  exit 1
fi

echo "▸ Stapling ticket to the installer"
xcrun stapler staple "$PKG"

echo "▸ Verifying"
xcrun stapler validate "$PKG"
spctl -a -vv --type install "$PKG"

echo "✓ Signed, notarized & stapled installer: $PKG"
