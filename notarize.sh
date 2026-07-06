#!/bin/bash
# Notarizes the Developer-ID-signed Lurent.app and staples the ticket, so the
# app passes Gatekeeper after being downloaded/copied to another Mac.
#
# One-time setup — store your Apple credentials in a keychain profile:
#
#   1. Create an app-specific password at https://account.apple.com → Sign-In
#      and Security → App-Specific Passwords.
#   2. Run:
#        xcrun notarytool store-credentials "lurent-notary" \
#          --apple-id "you@example.com" \
#          --team-id "6UQUNT93NG" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# Then build a signed app (./build.sh) and run this script.
# Override the profile name with NOTARY_PROFILE=... if you named it differently.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lurent.app"
ZIP="$ROOT/build/Lurent.zip"
PROFILE="${NOTARY_PROFILE:-lurent-notary}"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first." >&2; exit 1; }

# Refuse to notarize an ad-hoc build (notarytool would reject it anyway).
# Capture the output first: piping into `grep -q` under `pipefail` would fail the
# check with SIGPIPE when grep exits early, even on a validly signed app.
SIG_INFO="$(codesign -dvv "$APP" 2>&1 || true)"
if ! grep -q "Authority=Developer ID Application" <<<"$SIG_INFO"; then
  echo "✗ $APP is not Developer-ID signed." >&2
  echo "  Build with a Developer ID identity first:" >&2
  echo "    SIGN_IDENTITY=\"Developer ID Application: …\" ./build.sh" >&2
  exit 1
fi

echo "▸ Zipping app for submission"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Let notarytool itself be the source of truth: it reports a missing keychain
# profile locally and a network problem distinctly, so we don't pre-probe with a
# networked `notarytool history` (which would misreport an outage as a missing
# profile). On any failure, point at store-credentials in case the profile is it.
echo "▸ Submitting to Apple notary service (waits for the result)"
if ! xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait; then
  echo "✗ Notarization failed (see the error above)." >&2
  echo "  If it names a missing keychain profile \"$PROFILE\", create it once:" >&2
  echo "    xcrun notarytool store-credentials \"$PROFILE\" \\" >&2
  echo "      --apple-id \"you@example.com\" --team-id \"6UQUNT93NG\" --password \"xxxx-xxxx-xxxx-xxxx\"" >&2
  rm -f "$ZIP"
  exit 1
fi

echo "▸ Stapling ticket to the app"
xcrun stapler staple "$APP"

echo "▸ Verifying"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

rm -f "$ZIP"
echo "✓ Notarized & stapled: $APP"
