#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/upstream.lock"
PATCH_FILE="$ROOT_DIR/patches/0001-codex-mini-hud.patch"
HUD_VERSION="$(<"$ROOT_DIR/VERSION")"
DIST_DIR="${CODEX_HUD_DIST_DIR:-$ROOT_DIR/dist}"
WORK_DIR="${CODEX_HUD_BUILD_DIR:-}"
KEEP_BUILD="${CODEX_HUD_KEEP_BUILD:-0}"
TARGET="${CODEX_HUD_TARGET:-}"
PYTHON_BIN="${CODEX_HUD_PYTHON:-python3}"

die() {
  printf 'codex-mini-hud build: %s\n' "$*" >&2
  exit 1
}

[[ -r "$LOCK_FILE" ]] || die "missing upstream.lock"
[[ -r "$PATCH_FILE" ]] || die "missing HUD patch: $PATCH_FILE"

# shellcheck disable=SC1090
source "$LOCK_FILE"
[[ "$CODEX_TAG" == rust-v* ]] || die "invalid CODEX_TAG in upstream.lock"
[[ "$CODEX_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "invalid CODEX_COMMIT in upstream.lock"

if [[ -z "$TARGET" ]]; then
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) TARGET=aarch64-apple-darwin ;;
    Darwin:x86_64) TARGET=x86_64-apple-darwin ;;
    *) die "set CODEX_HUD_TARGET explicitly for this platform" ;;
  esac
fi

case "$TARGET" in
  aarch64-apple-darwin|x86_64-apple-darwin) ;;
  *) die "unsupported target: $TARGET" ;;
esac

command -v git >/dev/null 2>&1 || die "git is required"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "Python 3.10 or newer is required"
command -v strip >/dev/null 2>&1 || die "Apple strip is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
"$PYTHON_BIN" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' \
  || die "Python 3.10 or newer is required (set CODEX_HUD_PYTHON)"

created_work=0
if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-build.XXXXXX")"
  created_work=1
else
  mkdir -p "$WORK_DIR"
fi

cleanup() {
  if (( created_work )) && [[ "$KEEP_BUILD" != "1" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

SOURCE_DIR="$WORK_DIR/codex"
PACKAGE_DIR="$WORK_DIR/package"
ARCHIVE="$DIST_DIR/codex-mini-hud-$HUD_VERSION-codex-${CODEX_TAG#rust-v}-$TARGET.tar.gz"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/openai/codex.git "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --force --depth 1 origin \
  "$CODEX_COMMIT" "refs/tags/$CODEX_TAG:refs/tags/$CODEX_TAG"
git -C "$SOURCE_DIR" checkout --detach "$CODEX_COMMIT"
[[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$CODEX_COMMIT" ]] \
  || die "upstream checkout does not match lock"
[[ "$(git -C "$SOURCE_DIR" rev-list -n 1 "$CODEX_TAG")" == "$CODEX_COMMIT" ]] \
  || die "CODEX_TAG does not resolve to CODEX_COMMIT"

git -C "$SOURCE_DIR" apply --check "$PATCH_FILE"
git -C "$SOURCE_DIR" apply "$PATCH_FILE"

mkdir -p "$DIST_DIR"
"$PYTHON_BIN" "$SOURCE_DIR/scripts/build_codex_package.py" \
  --target "$TARGET" \
  --variant codex \
  --cargo-profile release \
  --package-dir "$PACKAGE_DIR"

# Upstream release binaries retain local symbols. Removing those symbols keeps
# public archives close to the official package size without changing runtime
# behavior. Signing, if a downstream distributor chooses it, happens later.
strip -x \
  "$PACKAGE_DIR/bin/codex" \
  "$PACKAGE_DIR/bin/codex-code-mode-host" \
  "$PACKAGE_DIR/codex-path/rg" \
  "$PACKAGE_DIR/codex-resources/zsh/bin/zsh"

mkdir -p "$PACKAGE_DIR/licenses"
cp "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/licenses/codex-mini-hud-MIT.txt"
cp "$ROOT_DIR/LICENSES/Apache-2.0.txt" "$PACKAGE_DIR/licenses/OpenAI-Codex-Apache-2.0.txt"
cp "$ROOT_DIR/LICENSES/ripgrep-MIT.txt" "$PACKAGE_DIR/licenses/ripgrep-MIT.txt"
cp "$ROOT_DIR/LICENSES/ripgrep-UNLICENSE.txt" "$PACKAGE_DIR/licenses/ripgrep-UNLICENSE.txt"
cp "$ROOT_DIR/LICENSES/zsh-LICENCE.txt" "$PACKAGE_DIR/licenses/zsh-LICENCE.txt"
cp "$ROOT_DIR/NOTICE" "$PACKAGE_DIR/NOTICE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$PACKAGE_DIR/THIRD_PARTY_NOTICES.md"

tar -czf "$ARCHIVE" -C "$PACKAGE_DIR" .

(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
printf 'Built %s\n' "$ARCHIVE"
