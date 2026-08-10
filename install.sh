#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--native" ]]; then
  shift
  exec "$SCRIPT_DIR/bin/codex-mini-hud" install "$@"
fi
exec "$SCRIPT_DIR/scripts/install-package.sh" "$@"
