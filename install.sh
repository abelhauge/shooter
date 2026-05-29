#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$ROOT_DIR/project.godot"
CHECK_ONLY=0
BOOTSTRAP_IMPORT=1

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check] [--no-bootstrap]

Installs or verifies local dependencies for this Godot 4 project.

Options:
  --check         Verify dependencies only; do not install anything.
  --no-bootstrap Skip Godot headless import/cache bootstrap.
  -h, --help     Show this help.
EOF
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

for arg in "$@"; do
  case "$arg" in
    --check)
      CHECK_ONLY=1
      ;;
    --no-bootstrap)
      BOOTSTRAP_IMPORT=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $arg"
      ;;
  esac
done

if [[ ! -f "$PROJECT_FILE" ]]; then
  die "Godot project not initialized yet. Expected $PROJECT_FILE"
fi

resolve_python() {
  if [[ -n "${PYTHON_BIN:-}" ]]; then
    if [[ "$PYTHON_BIN" == */* && -x "$PYTHON_BIN" ]]; then
      printf '%s\n' "$PYTHON_BIN"
    elif [[ "$PYTHON_BIN" == */* ]]; then
      return 1
    elif have "$PYTHON_BIN"; then
      command -v "$PYTHON_BIN"
    else
      return 1
    fi
  elif have python3; then
    command -v python3
  else
    return 1
  fi
}

resolve_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then
    if [[ "$GODOT_BIN" == */* && -x "$GODOT_BIN" ]]; then
      printf '%s\n' "$GODOT_BIN"
    elif [[ "$GODOT_BIN" == */* ]]; then
      return 1
    elif have "$GODOT_BIN"; then
      command -v "$GODOT_BIN"
    else
      return 1
    fi
  elif have godot4; then
    command -v godot4
  elif have godot; then
    command -v godot
  elif [[ -x "$ROOT_DIR/.bin/godot" ]]; then
    printf '%s\n' "$ROOT_DIR/.bin/godot"
  elif [[ "$(uname -s)" == "Darwin" && -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    printf '%s\n' "/Applications/Godot.app/Contents/MacOS/Godot"
  else
    return 1
  fi
}

link_macos_godot() {
  local app_bin="/Applications/Godot.app/Contents/MacOS/Godot"

  if [[ "$(uname -s)" != "Darwin" || ! -x "$app_bin" ]]; then
    return 0
  fi

  mkdir -p "$ROOT_DIR/.bin"
  ln -sf "$app_bin" "$ROOT_DIR/.bin/godot"
  log "Linked Godot app binary at .bin/godot"
}

install_with_brew() {
  if ! have brew; then
    die "Homebrew is required for automatic install on macOS. Install Homebrew or install Python 3 and Godot 4 manually."
  fi

  if ! resolve_python >/dev/null 2>&1; then
    log "Installing Python 3 with Homebrew"
    brew install python
  fi

  if ! resolve_godot >/dev/null 2>&1; then
    log "Installing Godot with Homebrew"
    brew install --cask godot || brew install godot
  fi

  link_macos_godot
}

install_with_apt() {
  local sudo_cmd=()
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo_cmd=(sudo)
  fi

  log "Installing packages with apt"
  "${sudo_cmd[@]}" apt-get update
  if ! resolve_python >/dev/null 2>&1; then
    "${sudo_cmd[@]}" apt-get install -y python3
  fi
  if ! resolve_godot >/dev/null 2>&1; then
    "${sudo_cmd[@]}" apt-get install -y godot4 || "${sudo_cmd[@]}" apt-get install -y godot || true
  fi
}

install_with_dnf() {
  local sudo_cmd=()
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo_cmd=(sudo)
  fi

  log "Installing packages with dnf"
  if ! resolve_python >/dev/null 2>&1; then
    "${sudo_cmd[@]}" dnf install -y python3
  fi
  if ! resolve_godot >/dev/null 2>&1; then
    "${sudo_cmd[@]}" dnf install -y godot || true
  fi
}

install_with_pacman() {
  local sudo_cmd=()
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo_cmd=(sudo)
  fi

  log "Installing packages with pacman"
  if ! resolve_python >/dev/null 2>&1; then
    "${sudo_cmd[@]}" pacman -S --needed --noconfirm python
  fi
  if ! resolve_godot >/dev/null 2>&1; then
    "${sudo_cmd[@]}" pacman -S --needed --noconfirm godot || true
  fi
}

install_dependencies() {
  case "$(uname -s)" in
    Darwin)
      install_with_brew
      ;;
    Linux)
      if have apt-get; then
        install_with_apt
      elif have dnf; then
        install_with_dnf
      elif have pacman; then
        install_with_pacman
      else
        die "Could not find apt-get, dnf, or pacman. Install Python 3 and Godot 4 manually."
      fi
      ;;
    *)
      die "Unsupported OS for automatic install. Install Python 3 and Godot 4 manually."
      ;;
  esac
}

check_asset_baseline() {
  local missing=0
  local required_assets=(
    "assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Large_2.gltf"
    "assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf"
    "assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx"
  )

  for asset_path in "${required_assets[@]}"; do
    if [[ ! -e "$ROOT_DIR/$asset_path" ]]; then
      warn "Missing local asset baseline file: $asset_path"
      missing=1
    fi
  done

  if [[ "$missing" -eq 1 ]]; then
    warn "Dependency install completed, but local Quaternius asset packs are incomplete. Restore assets/third_party/quaternius before opening the editor."
  fi
}

if [[ "$CHECK_ONLY" -eq 0 ]]; then
  install_dependencies
fi

PYTHON_BIN_RESOLVED="$(resolve_python || true)"
GODOT_BIN_RESOLVED="$(resolve_godot || true)"

if [[ -z "$PYTHON_BIN_RESOLVED" ]]; then
  die "Python 3 is missing. Run ./install.sh without --check to install it where supported."
fi

if [[ -z "$GODOT_BIN_RESOLVED" ]]; then
  die "Godot 4 is missing. Run ./install.sh without --check to install it where supported, or set GODOT_BIN=/path/to/Godot."
fi

GODOT_VERSION="$("$GODOT_BIN_RESOLVED" --version 2>/dev/null | head -n 1 || true)"
case "$GODOT_VERSION" in
  4.*)
    ;;
  *)
    die "Expected Godot 4, got '${GODOT_VERSION:-unknown}' from $GODOT_BIN_RESOLVED"
    ;;
esac

log "Python: $PYTHON_BIN_RESOLVED"
log "Godot: $GODOT_BIN_RESOLVED ($GODOT_VERSION)"

check_asset_baseline

if [[ "$BOOTSTRAP_IMPORT" -eq 1 ]]; then
  log "Bootstrapping Godot import/class cache"
  "$GODOT_BIN_RESOLVED" --headless --import --path "$ROOT_DIR"
fi

log "Running static validation"
"$PYTHON_BIN_RESOLVED" "$ROOT_DIR/tools/validate_static.py"

log "Install check complete. Start the game with ./run.sh or the editor with ./run.sh --editor"
