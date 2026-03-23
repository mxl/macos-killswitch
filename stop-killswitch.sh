#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(python3 - <<'PY' "${BASH_SOURCE[0]}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/killswitch.conf"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
  fi
}

require_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing ${CONFIG_FILE}. Run sudo ${SCRIPT_DIR}/install-killswitch.sh first."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
}

main() {
  require_root
  require_config

  cat > "$ANCHOR_PATH" <<'EOF'
# Kill switch disabled.
EOF

  chmod 600 "$ANCHOR_PATH"
  pfctl -nf "$PF_CONF"
  pfctl -f "$PF_CONF"
  pfctl -e >/dev/null 2>&1 || true

  echo "Kill switch disabled."
}

main "$@"
