#!/bin/bash
#
# Build a Release .app + .dmg for The Setup Engine.
#
# Two modes:
#   1. Ad-hoc (default, no Apple Developer account needed)
#      Produces an ad-hoc-signed .app that runs locally and on other machines
#      after right-click → Open (Gatekeeper warning).
#
#   2. Developer ID + notarization
#      Produces a notarized, stapled .app that runs cleanly anywhere.
#      Activated when DEVELOPMENT_TEAM is set in the environment.
#      Also requires:
#        - "Developer ID Application" cert in your keychain
#        - APPLE_ID, NOTARY_PASSWORD env vars (app-specific password)
#
# Examples:
#   ./scripts/release.sh
#   DEVELOPMENT_TEAM=ABC1234DEF \
#     APPLE_ID=you@example.com \
#     NOTARY_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#     ./scripts/release.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="The Setup Engine.xcodeproj"
SCHEME="The Setup Engine"
APP_NAME="The Setup Engine"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"
DMG_STAGE="$BUILD_DIR/dmg-staging"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "==> Developer ID build (team: $DEVELOPMENT_TEAM)"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        "CODE_SIGN_IDENTITY=Developer ID Application"
        "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"
    )
else
    echo "==> Ad-hoc build (no DEVELOPMENT_TEAM set)"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="-"
        DEVELOPMENT_TEAM=
    )
fi

echo "==> Building Release"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    "${SIGN_ARGS[@]}" \
    build \
    | xcbeautify --quiet 2>/dev/null || \
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    "${SIGN_ARGS[@]}" \
    build

test -d "$APP_PATH" || { echo "ERROR: $APP_PATH not found after build"; exit 1; }

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    : "${APPLE_ID:?APPLE_ID required for notarization}"
    : "${NOTARY_PASSWORD:?NOTARY_PASSWORD required for notarization (app-specific password)}"

    echo "==> Submitting to Apple notary service (this can take a few minutes)"
    NOTARY_ZIP="$BUILD_DIR/notary.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$DEVELOPMENT_TEAM" \
        --password "$NOTARY_PASSWORD" \
        --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_PATH"
fi

echo "==> Building DMG"
rm -rf "$DMG_STAGE"
mkdir "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG"

echo ""
echo "✓ App: $APP_PATH"
echo "✓ DMG: $DMG"
echo ""
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "Note: this is an ad-hoc-signed build."
    echo "On other machines, right-click → Open the first time to bypass Gatekeeper."
    echo "Or: xattr -d com.apple.quarantine '/Applications/$APP_NAME.app'"
fi
