#!/bin/zsh
# Baut DropMe.app (Apple Silicon) nach build/, mit --install zusätzlich nach ~/Applications und startet es,
# mit --zip zusätzlich build/DropMe-<Version>.zip für ein GitHub-Release.
#
# Signiert wird mit dem ersten „Developer ID Application“-Zertifikat im Schlüsselbund, sonst ad hoc.
# Mit --zip wird außerdem notarisiert, wenn ein notarytool-Profil existiert (Name in NOTARY_PROFILE,
# Standard „notary“, anlegen mit `xcrun notarytool store-credentials notary`).
set -euo pipefail
cd "${0:A:h}"

swift build -c release --disable-sandbox --arch arm64
BIN="$(swift build -c release --disable-sandbox --arch arm64 --show-bin-path)/DropMe"
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
    echo "Signiert: $IDENTITY"
else
    codesign --force --sign - --options runtime "$APP"
    echo "Signiert: ad hoc (kein Developer-ID-Zertifikat gefunden)"
fi
codesign --verify --strict "$APP"
echo "Gebaut: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/DropMe-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    if [[ -n "$IDENTITY" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
        echo "Notarisiert und geheftet"
    else
        echo "Nicht notarisiert (kein notarytool-Profil „$NOTARY_PROFILE“)"
    fi
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
