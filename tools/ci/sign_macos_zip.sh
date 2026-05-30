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

SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-${APPLE_CODESIGN_IDENTITY:--}}"
NOTARIZE_MODE="${MACOS_NOTARIZE:-auto}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-${MACOS_NOTARY_PROFILE:-}}"
APPLE_ID_VALUE="${APPLE_ID:-}"
APPLE_TEAM_ID_VALUE="${APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD_VALUE="${APPLE_APP_PASSWORD:-}"

has_notary_credentials() {
  [[ -n "$NOTARY_PROFILE" ]] || {
    [[ -n "$APPLE_ID_VALUE" ]] && [[ -n "$APPLE_TEAM_ID_VALUE" ]] && [[ -n "$APPLE_APP_PASSWORD_VALUE" ]]
  }
}

should_notarize=false
case "$NOTARIZE_MODE" in
  1|true|TRUE|yes|YES)
    should_notarize=true
    ;;
  0|false|FALSE|no|NO)
    should_notarize=false
    ;;
  auto)
    if [[ "$SIGN_IDENTITY" != "-" ]] && has_notary_credentials; then
      should_notarize=true
    fi
    ;;
  *)
    echo "MACOS_NOTARIZE must be one of auto, 1, or 0." >&2
    exit 2
    ;;
esac

if [[ "$should_notarize" == true ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Notarization requires MACOS_CODESIGN_IDENTITY/APPLE_CODESIGN_IDENTITY to be a Developer ID Application identity." >&2
    exit 1
  fi
  if ! has_notary_credentials; then
    echo "Notarization requires APPLE_NOTARY_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD." >&2
    exit 1
  fi
  if ! xcrun notarytool --help >/dev/null 2>&1; then
    echo "xcrun notarytool is required for notarization. Install current Xcode command line tools." >&2
    exit 1
  fi
  if ! xcrun stapler --help >/dev/null 2>&1; then
    echo "xcrun stapler is required for notarization stapling. Install current Xcode command line tools." >&2
    exit 1
  fi
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

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$should_notarize" == true ]]; then
  notary_args=(xcrun notarytool submit "$ZIP_PATH" --wait)
  if [[ -n "$NOTARY_PROFILE" ]]; then
    notary_args+=(--keychain-profile "$NOTARY_PROFILE")
  else
    notary_args+=(--apple-id "$APPLE_ID_VALUE" --team-id "$APPLE_TEAM_ID_VALUE" --password "$APPLE_APP_PASSWORD_VALUE")
  fi
  "${notary_args[@]}"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  echo "Developer ID signed, notarized, and stapled macOS app: $APP_PATH"
else
  echo "Signed macOS app without notarization: identity=$SIGN_IDENTITY app=$APP_PATH"
fi
