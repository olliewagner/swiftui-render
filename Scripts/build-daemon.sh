#!/bin/bash
set -euo pipefail

# Build the SwiftUI Render daemon app from source

SHARE_DIR="${HOME}/.local/share/swiftui-render"
DAEMON_SOURCE="${SHARE_DIR}/daemon.swift"
APP_DIR="${SHARE_DIR}/SwiftUIRenderDaemon.app/Contents"
BINARY="${APP_DIR}/MacOS/daemon"

if [ ! -f "${DAEMON_SOURCE}" ]; then
    echo "ERROR: daemon.swift not found at ${DAEMON_SOURCE}"
    echo "Place the daemon source file there first."
    exit 1
fi

echo "Building daemon..."
mkdir -p "${APP_DIR}/MacOS"

SDK_PATH=$(xcrun --show-sdk-path)

# Write Info.plist
cat > "${APP_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.swiftui-render.daemon</string>
<key>CFBundleExecutable</key><string>daemon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

xcrun swiftc -swift-version 5 -suppress-warnings \
    -parse-as-library \
    -target arm64-apple-ios17.0-macabi \
    -sdk "${SDK_PATH}" \
    -Fsystem "${SDK_PATH}/System/iOSSupport/System/Library/Frameworks" \
    -framework SwiftUI -framework UIKit \
    "${DAEMON_SOURCE}" \
    -o "${BINARY}"

echo "Daemon built: ${SHARE_DIR}/SwiftUIRenderDaemon.app"
