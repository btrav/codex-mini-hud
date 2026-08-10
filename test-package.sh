#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-package-tests.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT

case "$(uname -m)" in
  arm64) TARGET=aarch64-apple-darwin ;;
  x86_64) TARGET=x86_64-apple-darwin ;;
  *) printf 'Unsupported test architecture\n' >&2; exit 1 ;;
esac
# shellcheck disable=SC1090
source "$ROOT/upstream.lock"
UPSTREAM_VERSION="${CODEX_TAG#rust-v}"
HUD_VERSION="$(cat "$ROOT/VERSION")"

make_package() {
  local package="$1" target="${2:-$TARGET}"
  mkdir -p "$package/bin" "$package/codex-path" "$package/licenses"
  printf '{"layoutVersion":1,"version":"%s","target":"%s","variant":"codex","entrypoint":"bin/codex","resourcesDir":"codex-resources","pathDir":"codex-path"}\n' \
    "$UPSTREAM_VERSION" "$target" > "$package/codex-package.json"
  for executable in bin/codex bin/codex-code-mode-host codex-path/rg; do
    cp "$ROOT/tests/fixtures/fake-codex" "$package/$executable"
    chmod 755 "$package/$executable"
  done
  printf 'MIT fixture\n' > "$package/licenses/codex-mini-hud-MIT.txt"
  printf 'Apache-2.0 fixture\n' > "$package/licenses/OpenAI-Codex-Apache-2.0.txt"
  printf 'ripgrep MIT fixture\n' > "$package/licenses/ripgrep-MIT.txt"
  printf 'ripgrep Unlicense fixture\n' > "$package/licenses/ripgrep-UNLICENSE.txt"
  printf 'zsh licence fixture\n' > "$package/licenses/zsh-LICENCE.txt"
  printf 'Notice fixture\n' > "$package/NOTICE"
  printf 'Third-party fixture\n' > "$package/THIRD_PARTY_NOTICES.md"
}

use_home() {
  local name="$1"
  export HOME="$TEST_ROOT/home with spaces/$name"
  export CODEX_HUD_SHARE_ROOT="$HOME/share"
  export CODEX_HUD_BIN_DIR="$HOME/bin"
  export CODEX_HUD_ACTIVITY_DIR="$HOME/activity"
  export CODEX_HUD_PACKAGE_ROOT="$CODEX_HUD_SHARE_ROOT/current"
  mkdir -p "$HOME"
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'Expected failure: %s\n' "$label" >&2
    exit 1
  fi
}

package="$TEST_ROOT/package"
make_package "$package"

# Fresh install, launcher activity, idempotence, and uninstall.
use_home basic
"$ROOT/scripts/install-package.sh" --package-dir "$package" >/dev/null
[[ -x "$CODEX_HUD_BIN_DIR/codex-hud" ]]
[[ -L "$CODEX_HUD_SHARE_ROOT/current" ]]
[[ "$(readlink "$CODEX_HUD_SHARE_ROOT/current")" == "$CODEX_HUD_SHARE_ROOT/releases/$HUD_VERSION/$TARGET" ]]
"$CODEX_HUD_BIN_DIR/codex-hud" --version | grep -Fq 'codex-hud-test 0.0.0'

first_activity="$(cat "$CODEX_HUD_ACTIVITY_DIR/activity")"
"$CODEX_HUD_BIN_DIR/codex-hud" --version >/dev/null
[[ "$(cat "$CODEX_HUD_ACTIVITY_DIR/activity")" == "$first_activity" ]]

"$ROOT/scripts/install-package.sh" --package-dir "$package" >/dev/null
[[ "$(readlink "$CODEX_HUD_SHARE_ROOT/current")" == "$CODEX_HUD_SHARE_ROOT/releases/$HUD_VERSION/$TARGET" ]]
[[ -z "$(find "$CODEX_HUD_SHARE_ROOT/releases/$HUD_VERSION/$TARGET" -name '.current.*.tmp' -print -quit)" ]]

"$ROOT/scripts/uninstall-package.sh" >/dev/null
[[ ! -e "$CODEX_HUD_BIN_DIR/codex-hud" ]]
[[ ! -e "$CODEX_HUD_SHARE_ROOT/current" ]]

# Strict archive checksum and canonical package extraction.
use_home archive
archive_dir="$TEST_ROOT/archive"
mkdir -p "$archive_dir"
archive="$archive_dir/fake-package.tar.gz"
tar -czf "$archive" -C "$TEST_ROOT" package
(tar -tzf "$archive" | grep -Fq 'package/licenses/OpenAI-Codex-Apache-2.0.txt')
(tar -tzf "$archive" | grep -Fq 'package/licenses/ripgrep-MIT.txt')
(tar -tzf "$archive" | grep -Fq 'package/licenses/zsh-LICENCE.txt')
(tar -tzf "$archive" | grep -Fq 'package/NOTICE')
(cd "$archive_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
"$ROOT/scripts/install-package.sh" --archive "$archive" >/dev/null
"$CODEX_HUD_BIN_DIR/codex-hud" --version | grep -Fq 'codex-hud-test 0.0.0'
"$ROOT/scripts/uninstall-package.sh" >/dev/null

# A checksum record for any file other than the archive must not validate it.
use_home checksum-name
printf 'unrelated\n' > "$archive_dir/other"
(cd "$archive_dir" && shasum -a 256 other > "$(basename "$archive").sha256")
assert_fails "checksum names another file" \
  "$ROOT/scripts/install-package.sh" --archive "$archive"
[[ ! -e "$CODEX_HUD_SHARE_ROOT/current" ]]
(cd "$archive_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")

# Lock contention must preserve the lock owned by the other process.
use_home lock-owner
mkdir -p "$CODEX_HUD_SHARE_ROOT/install.lock"
assert_fails "install lock contention" \
  "$ROOT/scripts/install-package.sh" --package-dir "$package"
[[ -d "$CODEX_HUD_SHARE_ROOT/install.lock" ]]

# Upgrade must replace current itself, not move the new symlink into the old
# release directory (the default macOS mv behavior without -h).
use_home upgrade
old_release="$CODEX_HUD_SHARE_ROOT/releases/0.9.0/$TARGET"
mkdir -p "$(dirname "$old_release")"
cp -R "$package" "$old_release"
printf 'codex-mini-hud-release-v1\n0.9.0\n%s\n' "$TARGET" > "$old_release/.codex-mini-hud-release"
ln -s "$old_release" "$CODEX_HUD_SHARE_ROOT/current"
"$ROOT/scripts/install-package.sh" --package-dir "$package" >/dev/null
new_release="$CODEX_HUD_SHARE_ROOT/releases/$HUD_VERSION/$TARGET"
[[ "$(readlink "$CODEX_HUD_SHARE_ROOT/current")" == "$new_release" ]]
[[ -z "$(find "$old_release" -name '.current.*.tmp' -print -quit)" ]]

# A failure after current promotion rolls back current and removes the newly
# created release rather than leaving a half-installed transaction.
use_home rollback
old_release="$CODEX_HUD_SHARE_ROOT/releases/0.9.0/$TARGET"
mkdir -p "$(dirname "$old_release")"
cp -R "$package" "$old_release"
printf 'codex-mini-hud-release-v1\n0.9.0\n%s\n' "$TARGET" > "$old_release/.codex-mini-hud-release"
ln -s "$old_release" "$CODEX_HUD_SHARE_ROOT/current"
export CODEX_HUD_TESTING=1 CODEX_HUD_TEST_FAIL_LAUNCHER=1
assert_fails "launcher promotion rollback" \
  "$ROOT/scripts/install-package.sh" --package-dir "$package"
unset CODEX_HUD_TEST_FAIL_LAUNCHER CODEX_HUD_TESTING
[[ "$(readlink "$CODEX_HUD_SHARE_ROOT/current")" == "$old_release" ]]
[[ ! -e "$CODEX_HUD_SHARE_ROOT/releases/$HUD_VERSION/$TARGET" ]]
[[ ! -e "$CODEX_HUD_SHARE_ROOT/install.lock" ]]

# A traversal-bearing current link is never accepted as recursive deletion
# authority. This is a regression test for releases/../../victim.
use_home traversal
mkdir -p "$CODEX_HUD_SHARE_ROOT/releases" "$HOME/victim"
printf 'keep\n' > "$HOME/victim/file"
ln -s "$CODEX_HUD_SHARE_ROOT/releases/../../victim" "$CODEX_HUD_SHARE_ROOT/current"
assert_fails "unsafe uninstall current target" "$ROOT/scripts/uninstall-package.sh"
[[ -f "$HOME/victim/file" ]]
[[ ! -e "$CODEX_HUD_SHARE_ROOT/install.lock" ]]

# Manifest shape, target, executable set, and package-tree symlinks are strict.
use_home manifest
bad_manifest="$TEST_ROOT/bad-manifest"
make_package "$bad_manifest"
printf '{}\n' > "$bad_manifest/codex-package.json"
assert_fails "empty package manifest" \
  "$ROOT/scripts/install-package.sh" --package-dir "$bad_manifest"

wrong_target="$TEST_ROOT/wrong-target"
make_package "$wrong_target" wrong-apple-darwin
assert_fails "wrong package target" \
  "$ROOT/scripts/install-package.sh" --package-dir "$wrong_target"

symlink_parent="$TEST_ROOT/symlink-parent"
ln -s "$package" "$symlink_parent"
assert_fails "symlinked package directory" \
  "$ROOT/scripts/install-package.sh" --package-dir "$symlink_parent"

not_executable="$TEST_ROOT/not-executable"
make_package "$not_executable"
chmod 600 "$not_executable/codex-path/rg"
assert_fails "non-executable ripgrep" \
  "$ROOT/scripts/install-package.sh" --package-dir "$not_executable"

# Foreign and symlinked launchers are never replaced.
use_home foreign-launcher
mkdir -p "$CODEX_HUD_BIN_DIR"
printf '#!/usr/bin/env bash\n' > "$CODEX_HUD_BIN_DIR/codex-hud"
chmod 755 "$CODEX_HUD_BIN_DIR/codex-hud"
assert_fails "foreign launcher" \
  "$ROOT/scripts/install-package.sh" --package-dir "$package"

use_home symlink-launcher
mkdir -p "$CODEX_HUD_BIN_DIR" "$HOME/launcher-target"
ln -s "$HOME/launcher-target" "$CODEX_HUD_BIN_DIR/codex-hud"
assert_fails "symlinked launcher" \
  "$ROOT/scripts/install-package.sh" --package-dir "$package"

printf 'Package install/launcher/uninstall safety tests passed.\n'
