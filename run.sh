#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$ROOT_DIR/project.godot"
EDITOR_START_SCENE="res://scenes/maps/art/arena_downtown_01_art.tscn"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Godot project not initialized yet. Expected $PROJECT_FILE" >&2
  exit 1
fi

sync_github_before_run() {
  if [[ "${SHOOTER_SKIP_GIT_SYNC:-0}" == "1" ]]; then
    echo "Skipping GitHub sync because SHOOTER_SKIP_GIT_SYNC=1." >&2
    return
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "GitHub sync skipped: git was not found in PATH." >&2
    return
  fi
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "GitHub sync skipped: $ROOT_DIR is not a git worktree." >&2
    return
  fi

  local branch
  branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" == "HEAD" ]]; then
    echo "GitHub sync skipped: detached HEAD has no upstream branch." >&2
    return
  fi

  local upstream
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    echo "GitHub sync skipped: branch '$branch' has no upstream." >&2
    return
  fi

  echo "Syncing GitHub branch '$branch' with '$upstream'..." >&2
  if ! git -C "$ROOT_DIR" diff --quiet \
    || ! git -C "$ROOT_DIR" diff --cached --quiet \
    || [[ -n "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]]; then
    git -C "$ROOT_DIR" add -A
    if ! git -C "$ROOT_DIR" diff --cached --quiet; then
      git -C "$ROOT_DIR" commit -m "Auto sync before run"
    fi
  fi

  git -C "$ROOT_DIR" pull --no-rebase --no-edit
  git -C "$ROOT_DIR" push
}

sync_github_before_run

if [[ -n "${GODOT_BIN:-}" ]]; then
  if [[ "$GODOT_BIN" == */* && ! -x "$GODOT_BIN" ]]; then
    echo "GODOT_BIN is set but is not executable: $GODOT_BIN" >&2
    exit 1
  elif [[ "$GODOT_BIN" != */* ]] && ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    echo "GODOT_BIN is set but was not found in PATH: $GODOT_BIN" >&2
    exit 1
  fi
elif command -v godot4 >/dev/null 2>&1; then
  GODOT_BIN="godot4"
elif command -v godot >/dev/null 2>&1; then
  GODOT_BIN="godot"
elif [[ -x "$ROOT_DIR/.bin/godot" ]]; then
  GODOT_BIN="$ROOT_DIR/.bin/godot"
else
  echo "Could not find a Godot executable in PATH. Install Godot 4 or add it to PATH." >&2
  exit 1
fi

configure_editor_start_scene() {
  local scene_path="$1"
  local layout_file="$ROOT_DIR/.godot/editor/editor_layout.cfg"
  local layout_dir
  layout_dir="$(dirname "$layout_file")"
  mkdir -p "$layout_dir"

  if [[ ! -f "$layout_file" ]]; then
    {
      printf '[EditorNode]\n\n'
      printf 'open_scenes=PackedStringArray("%s")\n' "$scene_path"
      printf 'current_scene="%s"\n' "$scene_path"
      printf 'selected_main_editor_idx=1\n'
    } > "$layout_file"
    return
  fi

  local tmp_file="$layout_file.tmp"
  awk -v scene_path="$scene_path" '
    BEGIN {
      in_editor_node = 0
      saw_editor_node = 0
    }
    /^\[EditorNode\]$/ {
      in_editor_node = 1
      saw_editor_node = 1
      print
      print ""
      printf "open_scenes=PackedStringArray(\"%s\")\n", scene_path
      printf "current_scene=\"%s\"\n", scene_path
      next
    }
    /^\[/ && in_editor_node {
      in_editor_node = 0
    }
    in_editor_node && /^open_scenes=/ {
      next
    }
    in_editor_node && /^current_scene=/ {
      next
    }
    {
      print
    }
    END {
      if (!saw_editor_node) {
        print ""
        print "[EditorNode]"
        print ""
        printf "open_scenes=PackedStringArray(\"%s\")\n", scene_path
        printf "current_scene=\"%s\"\n", scene_path
      }
    }
  ' "$layout_file" > "$tmp_file"
  mv "$tmp_file" "$layout_file"
}

IS_EDITOR=0
BOOTSTRAP_CACHE=1
for arg in "$@"; do
  case "$arg" in
    --editor|-e)
      IS_EDITOR=1
      ;;
    --version|--help|-h)
      BOOTSTRAP_CACHE=0
      ;;
  esac
done

if [[ "${SHOOTER_SKIP_IMPORT_BOOTSTRAP:-0}" == "1" ]]; then
  BOOTSTRAP_CACHE=0
fi

if [[ "$BOOTSTRAP_CACHE" -eq 1 && "$IS_EDITOR" -eq 1 ]]; then
  echo "Importing Godot assets before opening the editor..." >&2
  "$GODOT_BIN" --headless --import --path "$ROOT_DIR"
  export SHOOTER_EDITOR_START_SCENE="${SHOOTER_EDITOR_START_SCENE:-$EDITOR_START_SCENE}"
  configure_editor_start_scene "$SHOOTER_EDITOR_START_SCENE"
elif [[ "$BOOTSTRAP_CACHE" -eq 1 && ! -f "$ROOT_DIR/.godot/global_script_class_cache.cfg" ]]; then
  echo "Bootstrapping Godot import/class cache..." >&2
  "$GODOT_BIN" --headless --import --path "$ROOT_DIR"
fi

exec "$GODOT_BIN" --path "$ROOT_DIR" "$@"
