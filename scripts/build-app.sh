#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
if [[ $# -ge 1 ]]; then CONFIG="$1"; fi
APP="$ROOT/dist/PowerSentry.app"
ICONSET="$ROOT/.build/AppIcon.iconset"

python3 Scripts/check-localizations.py
swift build -c "$CONFIG"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

cp ".build/$CONFIG/PowerSentry" "$APP/Contents/MacOS/PowerSentry"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/PowerSentry"

for localization in Resources/*.lproj; do
    [[ -d "$localization" ]] || continue
    ditto "$localization" "$APP/Contents/Resources/$(basename "$localization")"
done

make_icon() {
    local size="$1"
    local filename="$2"
    sips -s format png -z "$size" "$size" "Resources/AppIcon.png" --out "$ICONSET/$filename" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/PowerSentry" --localization-test

echo "Built and ad-hoc signed: $APP"
file "$APP/Contents/MacOS/PowerSentry"
file "$APP/Contents/Resources/AppIcon.icns"
