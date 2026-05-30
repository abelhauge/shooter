#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMIT_MESSAGE="${1:-Udgiv ændringer}"

if ! command -v git >/dev/null 2>&1; then
  echo "Could not publish: git was not found in PATH." >&2
  exit 1
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Could not publish: $ROOT_DIR is not a git worktree." >&2
  exit 1
fi

branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
if [[ "$branch" == "HEAD" ]]; then
  echo "Could not publish: detached HEAD has no branch to push." >&2
  exit 1
fi

git -C "$ROOT_DIR" add -A
if ! git -C "$ROOT_DIR" diff --cached --quiet; then
  git -C "$ROOT_DIR" commit -m "$COMMIT_MESSAGE"
else
  echo "No local changes to commit."
fi

upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -n "$upstream" ]]; then
  git -C "$ROOT_DIR" pull --no-rebase --no-edit
  git -C "$ROOT_DIR" push
else
  git -C "$ROOT_DIR" push -u origin "$branch"
fi
