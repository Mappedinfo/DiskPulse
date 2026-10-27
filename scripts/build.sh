#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
OPTIONS=(--disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")
APP="$ROOT/dist/DiskPulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
case "${1:-}" in
    --universal)
        BINARIES=()
        for ARCH in arm64 x86_64; do
            ARCH_OPTIONS=(--scratch-path "$ROOT/.build/release-$ARCH" --triple "$ARCH-apple-macosx14.0")
            swift build "${OPTIONS[@]}" "${ARCH_OPTIONS[@]}" -c release -debug-info-format none
            BIN="$(swift build "${OPTIONS[@]}" "${ARCH_OPTIONS[@]}" -c release -debug-info-format none --show-bin-path)"
            BINARIES+=("$BIN/DiskPulse")
        done
        lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DiskPulse"
        ARCH_LABEL=universal
        ;;
    "")
        swift build "${OPTIONS[@]}" -c release -debug-info-format none
        BIN="$(swift build "${OPTIONS[@]}" -c release -debug-info-format none --show-bin-path)"
        cp "$BIN/DiskPulse" "$APP/Contents/MacOS/DiskPulse"
        ARCH_LABEL="$(uname -m)"
        ;;
    *)
        echo "用法：./scripts/build.sh [--universal]" >&2
        exit 2
        ;;
esac
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
swift scripts/make-icon.swift "$ROOT/.build/AppIcon.iconset"
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ARCHIVE="$ROOT/dist/DiskPulse-macOS-$ARCH_LABEL.zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ARCHIVE"
echo "构建完成：$APP"
echo "安装包：$ARCHIVE"
