#!/bin/zsh
# Baut DropMe.app (Universal: Apple Silicon und Intel) nach build/, mit --install zusätzlich nach ~/Applications und startet es,
# mit --zip zusätzlich build/DropMe-<Version>.zip für ein GitHub-Release.
set -euo pipefail
cd "${0:A:h}"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --disable-sandbox $ARCHS
BIN="$(swift build -c release --disable-sandbox $ARCHS --show-bin-path)/DropMe"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

APP=build/DropMe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - --options runtime "$APP"
echo "Gebaut: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/DropMe-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Archiv: $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x DropMe || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/DropMe.app
    ditto "$APP" ~/Applications/DropMe.app
    open ~/Applications/DropMe.app
    echo "Installiert: ~/Applications/DropMe.app"
fi
