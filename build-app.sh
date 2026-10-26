#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
swift Resources/make-icon.swift
swift build -c release --arch arm64
APP="dist/SnapMark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SnapMark "$APP/Contents/MacOS/SnapMark"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Keep a stable designated requirement across local rebuilds. Without this,
# ad-hoc signing defaults to the binary's changing cdhash and macOS TCC treats
# every build as a different app, invalidating Screen Recording permission.
codesign --force --deep --sign - \
  --requirements '=designated => identifier "local.fatih.snapmark"' \
  "$APP"
echo "Built $PWD/$APP"
