#!/usr/bin/env bash

set -euo pipefail
umask 077

SHARE_ROOT="${CODEX_HUD_SHARE_ROOT:-$HOME/.local/share/codex-mini-hud}"
BIN_DIR="${CODEX_HUD_BIN_DIR:-$HOME/.local/bin}"
DRY_RUN=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1 && shift
(( $# == 0 )) || {
  printf 'Usage: ./uninstall.sh [--dry-run]\n' >&2
  exit 1
}

die() {
  printf 'codex-mini-hud uninstall: %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "package uninstallation currently supports macOS only"
case "$SHARE_ROOT:$BIN_DIR" in
  /*:/*) ;;
  *) die "install roots must be absolute paths" ;;
esac

check_safe_path() {
  local path="$1" rest component current=""
  [[ "$path" == /* ]] || return 1
  rest="${path#/}"
  while [[ -n "$rest" ]]; do
    case "$rest" in
      */*) component="${rest%%/*}"; rest="${rest#*/}" ;;
      *) component="$rest"; rest="" ;;
    esac
    [[ "$component" != "." && "$component" != ".." ]] || return 1
    [[ -n "$component" ]] || continue
    current="$current/$component"
    [[ ! -L "$current" ]] || return 1
  done
}

check_safe_path "$SHARE_ROOT" || die "unsafe or symlinked share root: $SHARE_ROOT"
check_safe_path "$BIN_DIR" || die "unsafe or symlinked bin directory: $BIN_DIR"

launcher="$BIN_DIR/codex-hud"
current="$SHARE_ROOT/current"
lock=""
lock_acquired=0

cleanup() {
  local status=$?
  if (( lock_acquired )); then
    rmdir "$lock" 2>/dev/null || true
  fi
  return "$status"
}
trap cleanup EXIT

# Lock before reading ownership or current state so install cannot change those
# paths between validation and deletion.
if [[ ! -d "$SHARE_ROOT" ]]; then
  if (( DRY_RUN )); then
    printf 'Remove launcher: %s\n' "$launcher"
    exit 0
  fi
  mkdir -p "$SHARE_ROOT"
fi
check_safe_path "$SHARE_ROOT" || die "unsafe or symlinked share root: $SHARE_ROOT"
lock="$SHARE_ROOT/install.lock"
if mkdir "$lock" 2>/dev/null; then
  lock_acquired=1
else
  die "another install or uninstall is in progress"
fi

if [[ -e "$launcher" || -L "$launcher" ]]; then
  [[ ! -L "$launcher" ]] || die "refusing symlinked launcher: $launcher"
  [[ -f "$launcher" ]] || die "refusing non-file launcher: $launcher"
  grep -Fq 'codex-mini-hud managed launcher' "$launcher" \
    || die "refusing unowned launcher: $launcher"
fi

release=""
if [[ -L "$current" ]]; then
  release="$(readlink "$current")"
  check_safe_path "$release" || die "unsafe current target: $release"
  case "$release" in
    "$SHARE_ROOT"/releases/*/*) ;;
    *) die "current target is outside managed releases: $release" ;;
  esac
  relative_release="${release#"$SHARE_ROOT/releases/"}"
  [[ -n "${relative_release%%/*}" && -n "${relative_release#*/}" && "${relative_release#*/}" != */* ]] \
    || die "current target is not a versioned release: $release"
  [[ -d "$release" && ! -L "$release" ]] || die "current release is missing or symlinked: $release"
  [[ "$(sed -n '1p' "$release/.codex-mini-hud-release" 2>/dev/null || true)" == "codex-mini-hud-release-v1" ]] \
    || die "current release does not have a valid ownership marker"
elif [[ -e "$current" ]]; then
  die "refusing non-symlink current path: $current"
fi

printf 'Remove launcher: %s\n' "$launcher"
[[ -n "$release" ]] && printf 'Remove release:  %s\n' "$release"
if (( DRY_RUN )); then
  rmdir "$lock"
  lock_acquired=0
  exit 0
fi

rm -f "$launcher" "$current"
if [[ -n "$release" ]]; then
  # The exact target was locked, lexically contained, symlink-free, exactly two
  # components below releases/, and marked as owned before reaching this point.
  rm -rf "$release"
fi
rmdir "$SHARE_ROOT/releases"/* 2>/dev/null || true
rmdir "$SHARE_ROOT/releases" 2>/dev/null || true
rmdir "$lock"
lock_acquired=0
trap - EXIT
rmdir "$SHARE_ROOT" 2>/dev/null || true
printf 'Uninstalled codex-hud. The official codex command was not changed.\n'
