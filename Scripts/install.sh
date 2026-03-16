#!/bin/bash
set -euo pipefail

# Install swiftui-render CLI and daemon

INSTALL_BIN="${HOME}/.local/bin"
INSTALL_SHARE="${HOME}/.local/share/swiftui-render"

echo "Building CLI (release)..."
swift build -c release 2>&1 | tail -1

echo "Installing CLI to ${INSTALL_BIN}/"
mkdir -p "${INSTALL_BIN}"
cp -f .build/release/swiftui-render "${INSTALL_BIN}/swiftui-render"

echo "Installing resources to ${INSTALL_SHARE}/"
mkdir -p "${INSTALL_SHARE}"

# Copy daemon source if it exists
if [ -f "${INSTALL_SHARE}/daemon.swift" ]; then
    echo "Daemon source already exists, keeping it"
else
    echo "Note: Place daemon.swift at ${INSTALL_SHARE}/daemon.swift to enable daemon mode"
fi

# Build daemon if source exists
if [ -f "${INSTALL_SHARE}/daemon.swift" ]; then
    echo "Building daemon..."
    "${INSTALL_BIN}/swiftui-render" daemon build
fi

echo ""
echo "Installed:"
echo "  CLI:    ${INSTALL_BIN}/swiftui-render"
if [ -d "${INSTALL_SHARE}/SwiftUIRenderDaemon.app" ]; then
    echo "  Daemon: ${INSTALL_SHARE}/SwiftUIRenderDaemon.app"
fi
echo ""
echo "Make sure ${INSTALL_BIN} is in your PATH."
"${INSTALL_BIN}/swiftui-render" --version
