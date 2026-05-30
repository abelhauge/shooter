#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ITCH_TARGET="${ITCH_TARGET:-abelhauge/shooter}"
GAME_VERSION_PREFIX="${GAME_VERSION_PREFIX:-0.1}"
GODOT_TEMPLATE_VERSION="${GODOT_TEMPLATE_VERSION:-4.6.3.stable}"
VERSION="${1:-${GAME_VERSION_PREFIX}.$(git -C "$ROOT_DIR" rev-list --count HEAD).local}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  if [[ -f "$TMP_DIR/project.godot" ]]; then
    cp "$TMP_DIR/project.godot" "$ROOT_DIR/project.godot"
  fi
  if [[ -f "$TMP_DIR/export_presets.cfg" ]]; then
    cp "$TMP_DIR/export_presets.cfg" "$ROOT_DIR/export_presets.cfg"
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -z "${BUTLER_API_KEY:-}" && -n "${ITCH_KEY:-}" ]]; then
  export BUTLER_API_KEY="$ITCH_KEY"
fi

if [[ -z "${BUTLER_API_KEY:-}" ]]; then
  echo "Missing ITCH_KEY or BUTLER_API_KEY in $ROOT_DIR/.env" >&2
  exit 1
fi

if ! command -v godot >/dev/null 2>&1 && ! command -v godot4 >/dev/null 2>&1; then
  echo "Godot 4 is required in PATH as godot or godot4." >&2
  exit 1
fi

if ! command -v butler >/dev/null 2>&1; then
  echo "butler is required in PATH. Install it from https://itch.io/docs/butler/installing.html" >&2
  exit 1
fi

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
  else
    GODOT_BIN="godot4"
  fi
fi

TEMPLATE_ROOT_MAC="$HOME/Library/Application Support/Godot/export_templates/$GODOT_TEMPLATE_VERSION"
TEMPLATE_ROOT_LINUX="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_VERSION"
if [[ ! -d "$TEMPLATE_ROOT_MAC" && ! -d "$TEMPLATE_ROOT_LINUX" ]]; then
  echo "Godot export templates are missing for $GODOT_TEMPLATE_VERSION." >&2
  echo "Install them in Godot: Editor -> Manage Export Templates." >&2
  exit 1
fi

cd "$ROOT_DIR"
cp project.godot "$TMP_DIR/project.godot"
cp export_presets.cfg "$TMP_DIR/export_presets.cfg"
echo "$VERSION" > build_version.txt
python3 tools/validate_static.py
python3 tools/ci/set_project_version.py "$VERSION"
"$GODOT_BIN" --headless --import --path "$ROOT_DIR"

rm -rf build/windows build/macos
mkdir -p build/windows build/macos
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "Windows Desktop" "build/windows/MovementFPS.exe"
cp build_version.txt build/windows/version.txt
"$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "macOS" "build/macos/MovementFPS.zip"
cp build_version.txt build/macos/version.txt

butler push "build/windows" "$ITCH_TARGET:windows" --userversion "$VERSION"
butler push "build/macos/MovementFPS.zip" "$ITCH_TARGET:mac" --userversion "$VERSION"
