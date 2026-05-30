#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: tools/ci/sign_macos_zip.sh path/to/MovementFPS.zip" >&2
  exit 2
fi

ZIP_PATH="$1"
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "macOS zip not found: $ZIP_PATH" >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "codesign is required to sign macOS builds. Run this on macOS." >&2
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "ditto is required to repackage signed macOS builds. Run this on macOS." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

UNPACK_DIR="$TMP_DIR/unpacked"
mkdir -p "$UNPACK_DIR"
unzip -q "$ZIP_PATH" -d "$UNPACK_DIR"

APP_PATH="$(find "$UNPACK_DIR" -maxdepth 2 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "No .app bundle found inside $ZIP_PATH" >&2
  exit 1
fi

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Ad-hoc signed macOS app: $APP_PATH"
