#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$ROOT_DIR/patches/0001-codex-mini-hud.patch"
PYTHON_BIN="${CODEX_HUD_PYTHON:-python3}"
UPSTREAM_REMOTE="https://github.com/openai/codex.git"
WORK_DIR=""

die() {
  printf 'codex-mini-hud upstream check: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}
trap cleanup EXIT

[[ -r "$ROOT_DIR/upstream.lock" ]] || die "missing upstream.lock"
[[ -r "$PATCH_FILE" ]] || die "missing HUD patch"
command -v git >/dev/null 2>&1 || die "git is required"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "Python 3.10 or newer is required"

# shellcheck disable=SC1090
source "$ROOT_DIR/upstream.lock"
CURRENT_TAG="$CODEX_TAG"

if [[ -n "${CODEX_HUD_UPSTREAM_TAG:-}" ]]; then
  CANDIDATE_TAG="$CODEX_HUD_UPSTREAM_TAG"
else
  CANDIDATE_TAG="$(
    git ls-remote --refs --tags "$UPSTREAM_REMOTE" 'rust-v*' \
      | awk -F/ '{print $3}' \
      | "$PYTHON_BIN" -c '
import re
import sys

best = None
for tag in sys.stdin:
    tag = tag.strip()
    match = re.fullmatch(r"rust-v(\d+)\.(\d+)\.(\d+)", tag)
    if match:
        value = tuple(int(part) for part in match.groups())
        if best is None or value > best[0]:
            best = (value, tag)
if best:
    print(best[1])
'
  )"
fi

[[ -n "$CANDIDATE_TAG" ]] || die "could not determine an upstream rust-v* tag"
if [[ "$CANDIDATE_TAG" == "$CURRENT_TAG" ]]; then
  printf 'Pinned upstream %s is the latest stable rust tag.\n' "$CURRENT_TAG"
  exit 0
fi

printf 'New upstream Codex tag detected: %s (pinned: %s)\n' "$CANDIDATE_TAG" "$CURRENT_TAG"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-upstream.XXXXXX")"
SOURCE_DIR="$WORK_DIR/codex"
git clone --filter=blob:none --no-checkout "$UPSTREAM_REMOTE" "$SOURCE_DIR"
git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$CANDIDATE_TAG:refs/tags/$CANDIDATE_TAG"
git -C "$SOURCE_DIR" checkout --detach "$CANDIDATE_TAG"

if git -C "$SOURCE_DIR" apply --check "$PATCH_FILE"; then
  printf 'The patch still applies to %s; update upstream.lock and run the full release verification.\n' "$CANDIDATE_TAG" >&2
else
  printf 'The patch no longer applies to %s; rebase the HUD patch before updating.\n' "$CANDIDATE_TAG" >&2
fi

# A newer upstream release is an actionable maintenance event even when the
# patch applies cleanly; fail the scheduled job so it is visible to maintainers.
exit 1
