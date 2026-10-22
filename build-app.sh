#!/bin/bash
# Builds RefChecker.app into ./build (requires Xcode or the Xcode Command Line Tools, macOS 13+).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RefChecker"

APP=build/RefChecker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RefChecker"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"   # ad-hoc signature so Gatekeeper lets it run locally

echo "Built $APP"
echo "Run it with:  open $APP   (or drag it to /Applications)"
