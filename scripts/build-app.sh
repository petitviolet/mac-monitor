#!/usr/bin/env bash
set -euo pipefail

APP="MacMonitor"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT/build/$APP.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT"
swift build -c release

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
# installは新しいファイルを作って置き換えるため、実行中のバイナリの署名を無効にしない。
install -m 755 "$ROOT/.build/release/$APP" "$APP_BUNDLE/Contents/MacOS/$APP"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT"/Resources/glyphs/*.png "$APP_BUNDLE/Contents/Resources/"

codesign --force --sign - "$APP_BUNDLE"
# OSはバンドルのディレクトリの更新時刻でアイコンのキャッシュを判定する。icnsを置き換えただけでは古い描画が残るので、
# 更新時刻を変えてからLaunchServicesへ登録し直す。
touch "$APP_BUNDLE" "$APP_BUNDLE/Contents"
"$LSREGISTER" -f "$APP_BUNDLE"
echo "Built $APP_BUNDLE"
