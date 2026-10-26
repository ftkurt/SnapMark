#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
./build-app.sh
mkdir -p release
rm -f release/SnapMark-arm64.zip release/SnapMark-arm64.zip.sha256
ditto -c -k --sequesterRsrc --keepParent dist/SnapMark.app release/SnapMark-arm64.zip
shasum -a 256 release/SnapMark-arm64.zip > release/SnapMark-arm64.zip.sha256
codesign --verify --deep --strict dist/SnapMark.app
echo "Created $project_dir/release/SnapMark-arm64.zip"
