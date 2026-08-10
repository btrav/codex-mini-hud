#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--native" ]]; then
  shift
  exec "$SCRIPT_DIR/bin/codex-mini-hud" uninstall "$@"
fi
exec "$SCRIPT_DIR/scripts/uninstall-package.sh" "$@"
