#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=""
if [[ $# -ge 1 ]]; then VERSION="$1"; fi
if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/package.sh <version>" >&2
    exit 2
fi
APP="$ROOT/dist/PowerSentry.app"
ARCH="$(uname -m)"

if [[ ! -d "$APP" ]]; then
    echo "Missing app bundle: $APP (run scripts/build-app.sh first)" >&2
    exit 1
fi
if [[ "$ARCH" != "arm64" ]]; then
    echo "This release workflow currently targets Apple Silicon; got $ARCH" >&2
    exit 1
fi

ZIP="$ROOT/dist/PowerSentry-$VERSION-$ARCH.zip"
DMG="$ROOT/dist/PowerSentry-$VERSION-$ARCH.dmg"
(
    cd "$ROOT/dist"
    rm -f "$(basename "$ZIP")" "$(basename "$DMG")" SHA256SUMS
    ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP")" "$(basename "$ZIP")"
    hdiutil create -volname "PowerSentry $VERSION" -srcfolder "$(basename "$APP")" -ov -format UDZO "$(basename "$DMG")"
    shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS
)

echo "Created: $ZIP"
echo "Created: $DMG"
echo "Created: $ROOT/dist/SHA256SUMS"
