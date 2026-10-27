#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/DiskPulse.app"
DEST="$HOME/Applications/DiskPulse.app"
if [[ ! -x "$APP/Contents/MacOS/DiskPulse" ]]; then
    /bin/bash "$ROOT/scripts/build.sh"
fi
if /usr/bin/pgrep -f '/DiskPulse.app/Contents/MacOS/DiskPulse' >/dev/null; then
    echo "请先在 DiskPulse 菜单栏面板中点击「退出」，再安装更新。历史记录会保留。"
    exit 1
fi
if [[ -e "$DEST" ]]; then
    IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
    [[ "$IDENTIFIER" == "info.mapped.DiskPulse" ]] || { echo "安装位置已有其他应用，已停止。"; exit 1; }
fi
mkdir -p "$HOME/Applications"
ditto "$APP" "$DEST"
codesign --verify --strict "$DEST"
open "$DEST"
echo "已安装并启动：$DEST"
echo "点击菜单栏容量环。在「偏好设置」中可开启登录启动。"
