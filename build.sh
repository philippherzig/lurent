#!/bin/bash
# Builds Lurent into a runnable .app bundle (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lurent.app"
BIN_DIR="$APP/Contents/MacOS"
BIN="$BIN_DIR/Lurent"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"   # arm64 on Apple Silicon, x86_64 on Intel

echo "▸ Cleaning previous build"
rm -rf "$APP"
mkdir -p "$BIN_DIR" "$APP/Contents/Resources"

echo "▸ Compiling ($ARCH)"
swiftc -O -parse-as-library \
  -sdk "$SDK" \
  -target "${ARCH}-apple-macos26.0" \
  -o "$BIN" \
  "$ROOT"/Sources/*.swift

echo "▸ Assembling bundle"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "▸ Copying localizations"
# Each Localizations/<lang>.lproj/Localizable.strings ships as a bundle
# localization; German is the base (the string literals in code are the keys).
if compgen -G "$ROOT/Localizations/*.lproj" >/dev/null; then
  cp -R "$ROOT/Localizations/"*.lproj "$APP/Contents/Resources/"
  echo "  ($(ls -d "$ROOT/Localizations/"*.lproj | wc -l | tr -d ' ') localizations)"
fi


echo "▸ Compiling app icon"
ACTOOL="$(xcrun -f actool 2>/dev/null || true)"
if [ -z "$ACTOOL" ] && [ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]; then
  ACTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
if [ -n "$ACTOOL" ] && [ -d "$ROOT/AppIcon.icon" ]; then
  ICON_OUT="$(mktemp -d)"
  if "$ACTOOL" "$ROOT/AppIcon.icon" --compile "$ICON_OUT" \
      --platform macosx --minimum-deployment-target 26.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "$ICON_OUT/partial-info.plist" >/tmp/actool.log 2>&1; then
    [ -f "$ICON_OUT/Assets.car" ] && cp "$ICON_OUT/Assets.car" "$APP/Contents/Resources/"
    [ -f "$ICON_OUT/AppIcon.icns" ] && cp "$ICON_OUT/AppIcon.icns" "$APP/Contents/Resources/"
    echo "  (icon compiled from AppIcon.icon)"
  else
    echo "  WARNING: actool failed to compile AppIcon.icon — continuing without app icon (see /tmp/actool.log)"
  fi
  rm -rf "$ICON_OUT"
else
  echo "  WARNING: actool not found or AppIcon.icon missing — continuing without app icon"
fi

echo "▸ Code signing"

ENTITLEMENTS="$ROOT/Lurent.entitlements"

# codesign with the hardened runtime; retry without a secure timestamp when the
# Apple timestamp server is unreachable (offline). Only a timestamped build can
# be notarized. Args: <identity> <entitlements-or-empty> <path>
sign_hardened() {
  local id="$1" ent="$2" path="$3"
  local args=(--force --options runtime --sign "$id")
  if [ -n "$ent" ]; then args+=(--entitlements "$ent"); fi
  if codesign "${args[@]}" --timestamp "$path" 2>/dev/null; then return 0; fi
  # Retry without a secure timestamp. The usual cause is an unreachable timestamp
  # server (offline), but any codesign failure lands here; if the real problem is
  # something else, this second attempt surfaces its error (stderr not silenced).
  echo "  ⚠ signing $(basename "$path") with a secure timestamp failed (offline?) — retrying without one"
  codesign "${args[@]}" --timestamp=none "$path"
}

# SIGN_IDENTITY controls how the bundle is signed:
#   unset / "auto" → auto-detect a "Developer ID Application" identity
#   "Developer ID Application: …" or a cert SHA-1 → sign with that identity
#   "-" → force ad-hoc (local use only)
# A Developer ID signature adds the hardened runtime + entitlements + a secure
# timestamp, so the result is ready for `./notarize.sh`. Ad-hoc runs locally but
# is rejected by Gatekeeper once downloaded.
SIGN_IDENTITY="${SIGN_IDENTITY-auto}"
if [ "$SIGN_IDENTITY" = "auto" ]; then
  # Capture first, then parse: `security … | awk …exit` can SIGPIPE-fail security
  # under `set -o pipefail` (the hazard notarize.sh/release.sh already avoid).
  IDENTITIES="$(security find-identity -v -p codesigning || true)"
  SIGN_IDENTITY="$(awk -F'"' '/Developer ID Application/ {print $2; exit}' <<<"$IDENTITIES")"
fi
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "  signing Lurent.app"
  sign_hardened "$SIGN_IDENTITY" "$ENTITLEMENTS" "$APP"
  echo "  ✓ signed: $SIGN_IDENTITY (hardened runtime + entitlements)"
  echo "    → run ./notarize.sh to distribute (re-run online first if a timestamp was skipped)"
else
  echo "  ad-hoc signing (local use only)"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
  echo "  ad-hoc signed — local use only (set SIGN_IDENTITY to a Developer ID to distribute)"
fi

echo "✓ Built: $APP"
echo "  Run with:  open \"$APP\""
