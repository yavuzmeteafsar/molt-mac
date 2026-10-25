#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

APP="${1:-build/Molt.app}"
OUTPUT="${2:?kullanım: make-dmg.sh <Molt.app> <çıktı.dmg>}"

[ -d "$APP" ] || { echo "Bulunamadı: $APP"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Molt.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
hdiutil create -volname "Molt" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUTPUT" >/dev/null
echo "✓ $OUTPUT"
