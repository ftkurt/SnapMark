#!/bin/zsh
set -euo pipefail

SYSTEM=false
SOURCE=false
for arg in "$@"; do
  case "$arg" in
    --system) SYSTEM=true ;;
    --source) SOURCE=true ;;
    -h|--help) echo "Usage: ./install.sh [--source] [--system]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$SYSTEM" == true ]]; then
  DESTINATION="/Applications/SnapMark.app"
else
  DESTINATION="$HOME/Applications/SnapMark.app"
  mkdir -p "$HOME/Applications"
fi

work_dir=""
cleanup() { [[ -n "$work_dir" && -d "$work_dir" ]] && rm -rf "$work_dir"; }
trap cleanup EXIT

if [[ "$SOURCE" == true ]]; then
  project_dir="${0:A:h}"
  "$project_dir/build-app.sh"
  source_app="$project_dir/dist/SnapMark.app"
else
  work_dir="$(mktemp -d)"
  archive="$work_dir/SnapMark-arm64.zip"
  curl -fL --retry 3 \
    https://github.com/ftkurt/SnapMark/releases/latest/download/SnapMark-arm64.zip \
    -o "$archive"
  ditto -x -k "$archive" "$work_dir"
  source_app="$work_dir/SnapMark.app"
fi

codesign --verify --deep --strict "$source_app"
pkill -x SnapMark 2>/dev/null || true
ditto "$source_app" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"

echo "Installed SnapMark at $DESTINATION"
echo "Open it once, then grant Screen Recording permission when requested."
