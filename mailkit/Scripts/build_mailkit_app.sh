#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAILKIT_DIR="$ROOT_DIR/mailkit"
BUILD_DIR="$MAILKIT_DIR/build"
APP_NAME="MailToNotes"
BUILT_APP="$BUILD_DIR/DerivedData/Build/Products/Debug/$APP_NAME.app"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "Xcode developer directory not found: $DEVELOPER_DIR" >&2
    exit 1
fi

export DEVELOPER_DIR

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

(
    cd "$MAILKIT_DIR"
    xcodegen generate
)

xcodebuild \
    -project "$MAILKIT_DIR/MailToNotes.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    build

if [[ "${1:-}" == "--install" ]]; then
    /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1

    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUILT_APP" "/Applications/$APP_NAME.app"

    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -u \
        "$BUILT_APP" 2>/dev/null || true

    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f \
        -R \
        -trusted \
        "/Applications/$APP_NAME.app"

    /usr/bin/open "/Applications/$APP_NAME.app"
    echo "Installed /Applications/$APP_NAME.app"
else
    echo "Built $BUILT_APP"
    echo "Run with --install to copy it to /Applications."
fi
