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
# Ad-hoc builds need an explicit stable requirement for Screen Recording
# permission to survive rebuilds. A certificate-backed signature gets its
# designated requirement from the certificate and bundle identifier instead.
signing_identity="${SNAPMARK_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - \
    --requirements '=designated => identifier "local.fatih.snapmark"' \
    "$APP"
else
  codesign --force --sign "$signing_identity" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $PWD/$APP"
