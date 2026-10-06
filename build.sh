#!/bin/sh
# Builds SpaceName.app in ./build. Pass --install to copy it to /Applications.
set -eu
cd "$(dirname "$0")"

APP=build/SpaceName.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos13 -o "$APP/Contents/MacOS/SpaceName" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x SpaceName || true
    rm -rf /Applications/SpaceName.app
    cp -R "$APP" /Applications/
    open /Applications/SpaceName.app
    echo "Installed to /Applications"
fi
