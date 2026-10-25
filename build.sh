#!/bin/sh
set -eu
cd "$(dirname "$0")"

APP_NAME="Molt"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
ARCHS="${ARCHS:-$(uname -m)}"
ENGINE_DIR="${ENGINE_DIR:-}"

command -v swiftc >/dev/null 2>&1 || {
    echo "swiftc bulunamadı. Önce: xcode-select --install"
    exit 1
}

echo "▸ Temizleniyor"
rm -rf "$APP" "$BUILD/obj"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses" "$BUILD/obj"

echo "▸ Simge"
ICON_SOURCE="Assets/AppIcon.png"
if [ ! -f "$ICON_SOURCE" ]; then
    ICON_SOURCE="$BUILD/icon_1024.png"
    [ -f "$ICON_SOURCE" ] || swift makeicon.swift "$ICON_SOURCE"
fi
if [ ! -f "$BUILD/AppIcon.icns" ] || [ "$ICON_SOURCE" -nt "$BUILD/AppIcon.icns" ]; then
    rm -rf "$BUILD/AppIcon.iconset"
    mkdir -p "$BUILD/AppIcon.iconset"
    for size in 16 32 128 256 512; do
        double=$((size * 2))
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$BUILD/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$double" "$double" "$ICON_SOURCE" --out "$BUILD/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

BINARIES=""
for arch in $ARCHS; do
    echo "▸ Derleniyor ($arch)"
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -framework AppKit \
        -module-name Molt Sources/*.swift \
        -o "$BUILD/obj/$APP_NAME-$arch"
    BINARIES="$BINARIES $BUILD/obj/$APP_NAME-$arch"
done
lipo -create $BINARIES -output "$APP/Contents/MacOS/$APP_NAME"

echo "▸ Paketleniyor"
cp Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/Licenses/Molt-LICENSE.txt"
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && ditto "$lproj" "$APP/Contents/Resources/$(basename "$lproj")"
done

if [ -n "$ENGINE_DIR" ]; then
    [ -x "$ENGINE_DIR/filee-cli" ] || {
        echo "ENGINE_DIR içinde filee-cli yok: $ENGINE_DIR"
        exit 1
    }
    echo "▸ Filee motoru gömülüyor"
    ditto "$ENGINE_DIR" "$APP/Contents/MacOS/engine"
    if [ -d "$ENGINE_DIR/../licenses" ]; then
        cp "$ENGINE_DIR"/../licenses/* "$APP/Contents/Resources/Licenses/"
    fi
fi

echo "▸ İmzalanıyor (ad-hoc)"
xattr -cr "$APP"
if [ -d "$APP/Contents/MacOS/engine" ]; then
    find "$APP/Contents/MacOS/engine" -type f | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2- |
        while IFS= read -r file; do
            codesign --force --sign - "$file" >/dev/null 2>&1 || true
        done
fi
if ! codesign --force --sign - "$APP" >/dev/null 2>"$BUILD/codesign.log"; then
    echo "! codesign başarısız ($(tail -1 "$BUILD/codesign.log")), kurulumda tekrar denenecek"
fi

echo "✓ $APP"

if [ "${1:-}" = "install" ]; then
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    ditto --noextattr "$APP" "$INSTALL_DIR/$APP_NAME.app"
    xattr -cr "$INSTALL_DIR/$APP_NAME.app"
    codesign --force --sign - "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1 && echo "▸ İmzalandı: $INSTALL_DIR/$APP_NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1 || true
    /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
    echo "✓ Kuruldu: $INSTALL_DIR/$APP_NAME.app"
    open "$INSTALL_DIR/$APP_NAME.app"
elif [ "${1:-}" = "run" ]; then
    open "$APP"
fi
