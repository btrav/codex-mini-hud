#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
PACKAGE_DIR=""
ARCHIVE=""
DRY_RUN=0
SHARE_ROOT="${CODEX_HUD_SHARE_ROOT:-$HOME/.local/share/codex-mini-hud}"
BIN_DIR="${CODEX_HUD_BIN_DIR:-$HOME/.local/bin}"

die() {
  printf 'codex-mini-hud install: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./install.sh (--package-dir DIR | --archive FILE) [--dry-run]

Installs a private patched Codex package as `codex-hud`.
The official `codex` executable and ~/.codex data are not replaced.

Options:
  --package-dir DIR  Canonical package produced by scripts/build.sh
  --archive FILE     Canonical .tar.gz package and adjacent .sha256 file
  --dry-run          Validate and print destinations without writing
EOF
}

while (( $# )); do
  case "$1" in
    --package-dir) [[ $# -ge 2 ]] || die "--package-dir requires a value"; PACKAGE_DIR="$2"; shift 2 ;;
    --archive) [[ $# -ge 2 ]] || die "--archive requires a value"; ARCHIVE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ -n "$PACKAGE_DIR" && -n "$ARCHIVE" ]] || [[ -z "$PACKAGE_DIR" && -z "$ARCHIVE" ]]; then
  die "choose exactly one of --package-dir or --archive"
fi

[[ "$(uname -s)" == "Darwin" ]] || die "package installation currently supports macOS only"
case "$(uname -m)" in
  arm64) target=aarch64-apple-darwin ;;
  x86_64) target=x86_64-apple-darwin ;;
  *) die "unsupported macOS architecture: $(uname -m)" ;;
esac

case "$SHARE_ROOT:$BIN_DIR" in
  /*:/*) ;;
  *) die "install roots must be absolute paths" ;;
esac

# Refuse traversal and every existing symlink in a managed path. Checking each
# component matters because testing only the final file still follows a
# symlinked parent directory.
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

work="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-install.XXXXXX")"
work="$(cd "$work" && pwd -P)"
lock=""
lock_acquired=0
stage=""
stage_created=0
current_tmp=""
launcher_tmp=""
release=""
release_created=0
previous_current=""
current_switched=0
committed=0

cleanup() {
  local status=$? rollback_succeeded=1
  [[ -z "$launcher_tmp" ]] || rm -f "$launcher_tmp"
  [[ -z "$current_tmp" ]] || rm -f "$current_tmp"
  if (( current_switched && ! committed )); then
    if [[ -n "$previous_current" ]]; then
      current_tmp="$SHARE_ROOT/.rollback.$$.tmp"
      rm -f "$current_tmp"
      if ln -s "$previous_current" "$current_tmp" \
        && mv -f -h "$current_tmp" "$SHARE_ROOT/current"; then
        current_tmp=""
      else
        rollback_succeeded=0
        rm -f "$current_tmp"
        current_tmp=""
      fi
    else
      rm -f "$SHARE_ROOT/current" || rollback_succeeded=0
    fi
  fi
  if (( release_created && ! committed && rollback_succeeded )) && [[ -n "$release" ]]; then
    rm -rf "$release"
  fi
  if (( stage_created )) && [[ -n "$stage" ]]; then
    rm -rf "$stage"
  fi
  rm -rf "$work"
  if (( lock_acquired )); then
    rmdir "$lock" 2>/dev/null || true
  fi
  return "$status"
}
trap cleanup EXIT

checksum_archive() {
  local archive checksum_file record expected expected_lower actual archive_name
  archive="$1"
  checksum_file="$archive.sha256"
  [[ -f "$archive" && ! -L "$archive" ]] || die "archive is missing or unsafe: $archive"
  [[ -f "$checksum_file" && ! -L "$checksum_file" ]] || die "missing checksum: $checksum_file"
  record="$(awk 'NF { count++; record=$0 } END { if (count != 1) exit 1; print record }' "$checksum_file")" \
    || die "checksum file must contain exactly one record"
  expected="${record%% *}"
  archive_name="$(basename "$archive")"
  [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || die "checksum file does not contain a SHA-256 digest"
  [[ "$record" == "$expected  $archive_name" ]] \
    || die "checksum record must name exactly $archive_name"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  expected_lower="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  [[ "$actual" == "$expected_lower" ]] || die "archive checksum did not match"
}

manifest_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

validate_package() {
  local package expected_target manifest expected_upstream
  package="$1"
  expected_target="$2"
  manifest="$package/codex-package.json"
  check_safe_path "$package" || die "unsafe or symlinked package path: $package"
  [[ -d "$package" && ! -L "$package" ]] || die "package directory is missing or unsafe"
  if find "$package" -type l -print -quit | grep -q .; then
    die "package contains a symbolic link"
  fi
  for required in \
    codex-package.json \
    bin/codex \
    bin/codex-code-mode-host \
    codex-path/rg \
    licenses/codex-mini-hud-MIT.txt \
    licenses/OpenAI-Codex-Apache-2.0.txt \
    licenses/ripgrep-MIT.txt \
    licenses/ripgrep-UNLICENSE.txt \
    licenses/zsh-LICENCE.txt \
    NOTICE \
    THIRD_PARTY_NOTICES.md; do
    [[ -e "$package/$required" && ! -L "$package/$required" ]] \
      || die "package is missing or has unsafe entry: $required"
  done
  for executable in bin/codex bin/codex-code-mode-host codex-path/rg; do
    [[ -f "$package/$executable" && -x "$package/$executable" ]] \
      || die "package executable is not runnable: $executable"
  done
  # shellcheck disable=SC1090
  source "$ROOT_DIR/upstream.lock"
  expected_upstream="${CODEX_TAG#rust-v}"
  [[ "$(manifest_value "$manifest" layoutVersion)" == "1" ]] || die "unsupported package layout"
  [[ "$(manifest_value "$manifest" version)" == "$expected_upstream" ]] || die "package version does not match upstream.lock"
  [[ "$(manifest_value "$manifest" target)" == "$expected_target" ]] || die "package target does not match this Mac"
  [[ "$(manifest_value "$manifest" variant)" == "codex" ]] || die "package variant is not codex"
  [[ "$(manifest_value "$manifest" entrypoint)" == "bin/codex" ]] || die "package entrypoint is not bin/codex"
}

prune_retired_releases() {
  local version_dir candidate
  [[ -d "$SHARE_ROOT/releases" && ! -L "$SHARE_ROOT/releases" ]] || return 0
  for version_dir in "$SHARE_ROOT/releases"/*; do
    [[ -d "$version_dir" && ! -L "$version_dir" ]] || continue
    for candidate in "$version_dir"/*; do
      [[ -d "$candidate" && ! -L "$candidate" ]] || continue
      [[ "$candidate" != "$release" ]] || continue
      check_safe_path "$candidate" || continue
      [[ "$(sed -n '1p' "$candidate/.codex-mini-hud-release" 2>/dev/null || true)" == "codex-mini-hud-release-v1" ]] \
        || continue
      rm -rf "$candidate"
      printf 'Pruned retired release: %s\n' "$candidate"
    done
    rmdir "$version_dir" 2>/dev/null || true
  done
}

if [[ -n "$ARCHIVE" ]]; then
  if [[ "$ARCHIVE" != /* ]]; then
    archive_candidate="$PWD/$ARCHIVE"
    check_safe_path "$archive_candidate" || die "unsafe or symlinked archive path: $ARCHIVE"
    ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
  else
    check_safe_path "$ARCHIVE" || die "unsafe or symlinked archive path: $ARCHIVE"
  fi
  checksum_archive "$ARCHIVE"
  if tar -tzf "$ARCHIVE" | awk '/(^|\/)\.\.($|\/)|^\// { bad=1 } END { exit bad ? 0 : 1 }'; then
    die "archive contains an unsafe path"
  fi
  tar -xzf "$ARCHIVE" -C "$work"
  if find "$work" -type l -print -quit | grep -q .; then
    die "archive contains a symbolic link"
  fi
  manifest_count="$(find "$work" -name codex-package.json -type f | awk 'END { print NR }')"
  [[ "$manifest_count" == "1" ]] || die "archive must contain exactly one canonical Codex package"
  manifest="$(find "$work" -name codex-package.json -type f -print -quit)"
  PACKAGE_DIR="$(dirname "$manifest")"
else
  if [[ "$PACKAGE_DIR" != /* ]]; then
    package_candidate="$PWD/$PACKAGE_DIR"
  else
    package_candidate="$PACKAGE_DIR"
  fi
  check_safe_path "$package_candidate" || die "unsafe or symlinked package path: $PACKAGE_DIR"
  PACKAGE_DIR="$(cd "$PACKAGE_DIR" && pwd)"
fi

validate_package "$PACKAGE_DIR" "$target"

release="$SHARE_ROOT/releases/$VERSION/$target"
launcher="$BIN_DIR/codex-hud"
printf 'Package:  %s\nRelease:  %s\nLauncher: %s\n' "$PACKAGE_DIR" "$release" "$launcher"
(( DRY_RUN )) && exit 0

mkdir -p "$SHARE_ROOT" "$BIN_DIR"
check_safe_path "$SHARE_ROOT" || die "unsafe or symlinked share root: $SHARE_ROOT"
check_safe_path "$BIN_DIR" || die "unsafe or symlinked bin directory: $BIN_DIR"
lock="$SHARE_ROOT/install.lock"
if mkdir "$lock" 2>/dev/null; then
  lock_acquired=1
else
  die "another install or uninstall is in progress"
fi

if [[ -L "$launcher" ]]; then
  die "refusing symlinked launcher: $launcher"
fi
if [[ -e "$launcher" ]] && ! grep -Fq 'codex-mini-hud managed launcher' "$launcher" 2>/dev/null; then
  die "refusing to replace an unowned launcher: $launcher"
fi

if [[ -L "$SHARE_ROOT/current" ]]; then
  previous_current="$(readlink "$SHARE_ROOT/current")"
  check_safe_path "$previous_current" || die "current package points to an unsafe path"
  [[ "$previous_current" == "$SHARE_ROOT"/releases/*/* ]] \
    || die "current package is outside the managed releases directory"
  [[ "$(sed -n '1p' "$previous_current/.codex-mini-hud-release" 2>/dev/null || true)" == "codex-mini-hud-release-v1" ]] \
    || die "current package does not have an ownership marker"
elif [[ -e "$SHARE_ROOT/current" ]]; then
  die "refusing non-symlink current package path"
fi

stage="$SHARE_ROOT/.release.$$.tmp"
[[ ! -e "$stage" && ! -L "$stage" ]] || die "staging path already exists"
mkdir -p "$(dirname "$release")"
cp -R "$PACKAGE_DIR" "$stage"
stage_created=1
printf 'codex-mini-hud-release-v1\n%s\n%s\n' "$VERSION" "$target" > "$stage/.codex-mini-hud-release"
validate_package "$stage" "$target"
"$stage/bin/codex" --version >/dev/null || die "patched Codex smoke test failed"

if [[ -e "$release" || -L "$release" ]]; then
  [[ -d "$release" && ! -L "$release" ]] \
    || die "existing release path is not owned by codex-mini-hud"
  [[ "$(sed -n '1p' "$release/.codex-mini-hud-release" 2>/dev/null || true)" == "codex-mini-hud-release-v1" ]] \
    || die "existing release path is not owned by codex-mini-hud"
  validate_package "$release" "$target"
  rm -rf "$stage"
  stage_created=0
else
  mv "$stage" "$release"
  stage_created=0
  release_created=1
fi

current_tmp="$SHARE_ROOT/.current.$$.tmp"
ln -s "$release" "$current_tmp"
mv -f -h "$current_tmp" "$SHARE_ROOT/current"
current_tmp=""
current_switched=1

if [[ "${CODEX_HUD_TESTING:-0}" == "1" && "${CODEX_HUD_TEST_FAIL_LAUNCHER:-0}" == "1" ]]; then
  die "injected launcher promotion failure"
fi

launcher_tmp="$BIN_DIR/.codex-hud.$$.tmp"
cp "$ROOT_DIR/bin/codex-hud" "$launcher_tmp"
chmod 755 "$launcher_tmp"
mv -f -h "$launcher_tmp" "$launcher"
launcher_tmp=""
committed=1

# The installed package is a complete Codex distribution. Once the new package
# and launcher have both been promoted, owned older releases are no longer
# needed and would otherwise accumulate hundreds of megabytes per upgrade.
prune_retired_releases

rmdir "$lock"
lock_acquired=0
printf 'Installed. Start with: %s\n' "$launcher"
