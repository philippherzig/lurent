#!/bin/bash
# Downloads a pinned Sparkle release into ./vendor/Sparkle (gitignored) so the
# no-Xcode build can embed Sparkle.framework and use its signing tools. Verifies
# the download against a pinned SHA-256 checksum (build.sh then re-signs the
# framework with your Developer ID for the hardened runtime).
set -euo pipefail

VERSION="2.9.4"
SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/Sparkle"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"

if [ -d "$DEST/Sparkle.framework" ] && [ -x "$DEST/bin/sign_update" ]; then
  echo "▸ Sparkle $VERSION already vendored → $DEST"
  exit 0
fi

echo "▸ Downloading Sparkle $VERSION"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/sparkle.tar.xz"

echo "▸ Verifying checksum"
echo "$SHA256  $TMP/sparkle.tar.xz" | shasum -a 256 -c -

echo "▸ Extracting → $DEST"
rm -rf "$DEST"; mkdir -p "$DEST"
tar -xJf "$TMP/sparkle.tar.xz" -C "$DEST"

[ -d "$DEST/Sparkle.framework" ] || { echo "✗ Sparkle.framework missing after extract" >&2; exit 1; }
[ -x "$DEST/bin/sign_update" ]   || { echo "✗ bin/sign_update missing after extract" >&2; exit 1; }

echo "✓ Sparkle $VERSION vendored → $DEST"
echo "  (build.sh re-signs Sparkle.framework with your Developer ID for the hardened runtime)"
