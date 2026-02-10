#!/bin/bash
# build-app.sh — Build VOX.app bundle from Swift Package Manager project
#
# Usage:
#   ./scripts/build-app.sh              # Build and create .app in build/
#   ./scripts/build-app.sh --install    # Build and copy to /Applications
#   ./scripts/build-app.sh --open       # Build and launch immediately

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="VOX"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
VERSION=$(cat "${PROJECT_DIR}/VERSION" 2>/dev/null || echo "0.0.0")

# Parse arguments
INSTALL=false
OPEN=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --open)    OPEN=true ;;
        --help|-h)
            echo "Usage: $0 [--install] [--open]"
            echo "  --install  Copy VOX.app to /Applications"
            echo "  --open     Launch VOX after building"
            exit 0
            ;;
    esac
done

echo "==> Building VOX v${VERSION}..."

# Step 1: Build release binary
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5
echo "    Binary compiled."

# Step 2: Locate the binary
BINARY=$(swift build -c release --show-bin-path)/VOX
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# Step 3: Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Step 4: Copy binary
cp "$BINARY" "${APP_BUNDLE}/Contents/MacOS/VOX"

# Step 5: Copy Info.plist (with version injected)
sed "s|<string>0.2.0</string>|<string>${VERSION}</string>|" \
    "${PROJECT_DIR}/Assets/Info.plist" > "${APP_BUNDLE}/Contents/Info.plist"

# Step 6: Copy icon
cp "${PROJECT_DIR}/Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Step 7: Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "==> VOX.app created at: ${APP_BUNDLE}"
echo "    Version: ${VERSION}"
echo "    Size: $(du -sh "$APP_BUNDLE" | cut -f1)"

# Install to /Applications if requested
if [ "$INSTALL" = true ]; then
    echo "==> Installing to /Applications..."
    # Kill running instances first
    pkill -f "VOX.app/Contents/MacOS/VOX" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/VOX.app"
    cp -R "$APP_BUNDLE" "/Applications/VOX.app"
    echo "    Installed at /Applications/VOX.app"
fi

# Open if requested
if [ "$OPEN" = true ]; then
    TARGET="$APP_BUNDLE"
    [ "$INSTALL" = true ] && TARGET="/Applications/VOX.app"
    echo "==> Launching VOX..."
    open "$TARGET"
fi

echo "==> Done!"
