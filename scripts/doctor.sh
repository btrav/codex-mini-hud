#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUD_VERSION="$(cat "$ROOT_DIR/VERSION")"
PACKAGE_ROOT="${CODEX_HUD_PACKAGE_ROOT:-$HOME/.local/share/codex-mini-hud/current}"
LAUNCHER="${CODEX_HUD_LAUNCHER:-$HOME/.local/bin/codex-hud}"

printf 'Codex Mini HUD: %s\n' "$HUD_VERSION"
printf 'Pinned upstream: '
(source "$ROOT_DIR/upstream.lock"; printf '%s (%s)\n' "$CODEX_TAG" "$CODEX_COMMIT")

if command -v codex >/dev/null 2>&1; then
  printf 'Official Codex:  %s\n' "$(codex --version 2>/dev/null || printf 'present, version unavailable')"
  printf 'Official path:   %s\n' "$(command -v codex)"
else
  printf 'Official Codex:  not found (optional fallback unavailable)\n'
fi

if [[ -x "$PACKAGE_ROOT/bin/codex" ]]; then
  printf 'Patched Codex:   %s\n' "$("$PACKAGE_ROOT/bin/codex" --version 2>/dev/null || printf 'version unavailable')"
  printf 'Package path:    %s\n' "$PACKAGE_ROOT"
else
  printf 'Patched Codex:   not installed\n'
fi

if [[ -x "$LAUNCHER" ]] && grep -Fq 'codex-mini-hud managed launcher' "$LAUNCHER"; then
  printf 'Launcher:        %s (owned)\n' "$LAUNCHER"
else
  printf 'Launcher:        missing or unowned: %s\n' "$LAUNCHER"
fi
