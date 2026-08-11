#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--native" ]]; then
  shift
  printf 'codex-mini-hud: --native is an advanced stock-Codex fallback; it does not provide the custom HUD bars or metrics.\n' >&2
  exec "$SCRIPT_DIR/bin/codex-mini-hud" install "$@"
fi
exec "$SCRIPT_DIR/scripts/install-package.sh" "$@"
