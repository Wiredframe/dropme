#!/bin/zsh
# Builds DropMe.app (Apple Silicon) into build/; with --install also copies it to ~/Applications and launches it,
# with --zip also creates build/DropMe-<version>.zip for a GitHub release.
#
# Signs with the first “Developer ID Application” certificate in the keychain, otherwise ad hoc.
# With --zip it also notarizes if a notarytool profile exists (name in NOTARY_PROFILE,
# default “notary”, create it with `xcrun notarytool store-credentials notary`).
set -euo pipefail
cd "${0:A:h}"

# Otherwise SwiftPM records the deployment target as the SDK version and macOS shows the app in the legacy look
# (small traffic lights, old controls). Linking with the real SDK version gets the current design.
SDK="$(xcrun --show-sdk-version)"
FLAGS=(-c release --disable-sandbox --arch arm64 -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK")
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/DropMe"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
NOTARY_PROFILE=${NOTARY_PROFILE:-notary}

APP=build/DropMe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
    echo "Signed: $IDENTITY"
else
    codesign --force --sign - --options runtime "$APP"
    echo "Signed: ad hoc (no Developer ID certificate found)"
fi
codesign --verify --strict "$APP"
echo "Built: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/DropMe-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    if [[ -n "$IDENTITY" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
        echo "Notarized and stapled"
    else
        echo "Not notarized (no notarytool profile “$NOTARY_PROFILE”)"
    fi
    echo "Archive: $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x DropMe || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/DropMe.app
    ditto "$APP" ~/Applications/DropMe.app
    open ~/Applications/DropMe.app
    echo "Installed: ~/Applications/DropMe.app"
fi
