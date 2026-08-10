#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'codex-mini-hud verify: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 2 ]] || die "usage: $0 ARCHIVE TARGET"
ARCHIVE="$1"
TARGET="$2"
[[ -f "$ARCHIVE" ]] || die "archive not found: $ARCHIVE"
[[ "$TARGET" == aarch64-apple-darwin || "$TARGET" == x86_64-apple-darwin ]] \
  || die "unsupported target: $TARGET"

command -v shasum >/dev/null 2>&1 || die "shasum is required"
command -v lipo >/dev/null 2>&1 || die "lipo is required"

CHECKSUM="$ARCHIVE.sha256"
[[ -f "$CHECKSUM" ]] || die "checksum not found: $CHECKSUM"
(cd "$(dirname "$ARCHIVE")" && shasum -a 256 -c "$(basename "$CHECKSUM")")

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-mini-hud-verify.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
tar -xzf "$ARCHIVE" -C "$TEMP_DIR"

for required in \
  codex-package.json \
  bin/codex \
  bin/codex-code-mode-host \
  codex-path/rg \
  codex-resources/zsh/bin/zsh \
  licenses/codex-mini-hud-MIT.txt \
  licenses/OpenAI-Codex-Apache-2.0.txt \
  licenses/ripgrep-MIT.txt \
  licenses/ripgrep-UNLICENSE.txt \
  licenses/zsh-LICENCE.txt \
  NOTICE \
  THIRD_PARTY_NOTICES.md; do
  [[ -e "$TEMP_DIR/$required" && ! -L "$TEMP_DIR/$required" ]] \
    || die "archive is missing or has unsafe entry: $required"
done

python3 - "$TEMP_DIR/codex-package.json" "$TARGET" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
if manifest.get("layoutVersion") != 1:
    raise SystemExit("unexpected package layout version")
if manifest.get("target") != sys.argv[2]:
    raise SystemExit("package target does not match expected target")
if manifest.get("entrypoint") != "bin/codex":
    raise SystemExit("unexpected package entrypoint")
PY

case "$TARGET" in
  aarch64-apple-darwin) expected_arch=arm64 ;;
  x86_64-apple-darwin) expected_arch=x86_64 ;;
esac

for executable in \
  bin/codex \
  bin/codex-code-mode-host \
  codex-path/rg \
  codex-resources/zsh/bin/zsh; do
  [[ -x "$TEMP_DIR/$executable" ]] || die "not executable: $executable"
  lipo -archs "$TEMP_DIR/$executable" | tr ' ' '\n' | grep -Fxq "$expected_arch" \
    || die "$executable does not contain architecture $expected_arch"
done

host_arch="$(uname -m)"
if [[ "$host_arch:$expected_arch" == arm64:arm64 || "$host_arch:$expected_arch" == x86_64:x86_64 ]]; then
  CODEX_MINI_HUD=1 "$TEMP_DIR/bin/codex" --version >/dev/null
fi

printf 'Verified %s (%s)\n' "$ARCHIVE" "$TARGET"
