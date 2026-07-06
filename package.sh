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

echo "▸ Building signed installer → $PKG"
productbuild --component "$APP" /Applications --sign "$INSTALL_IDENTITY" "$PKG"
echo "  ✓ signed: $INSTALL_IDENTITY"

echo "▸ Notarizing the installer (waits for the result)"
xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait

echo "▸ Stapling ticket to the installer"
xcrun stapler staple "$PKG"

echo "▸ Verifying"
xcrun stapler validate "$PKG"
spctl -a -vv --type install "$PKG"

echo "✓ Signed, notarized & stapled installer: $PKG"
