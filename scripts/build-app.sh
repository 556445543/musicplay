#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
    for candidate in /Applications/Xcode*.app; do
        if [ -d "$candidate/Contents/Developer" ]; then
            export DEVELOPER_DIR="$candidate/Contents/Developer"
            break
        fi
    done
fi

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet
fi

xcodebuild \
    -project MusicPlay.xcodeproj \
    -scheme MusicPlay \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    -quiet \
    build

APP="build/MusicPlay.app"
rm -rf "$APP"
cp -R "build/DerivedData/Build/Products/Release/MusicPlay.app" "$APP"

echo "已生成 $APP"
echo "运行：open \"$APP\""
