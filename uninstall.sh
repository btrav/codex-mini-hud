#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--native" ]]; then
  shift
  printf 'codex-mini-hud: removing the advanced native footer preset.\n' >&2
  exec "$SCRIPT_DIR/bin/codex-mini-hud" uninstall "$@"
fi
exec "$SCRIPT_DIR/scripts/uninstall-package.sh" "$@"
