#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(python3 - <<'PY' "${BASH_SOURCE[0]}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
INTERVAL="${1:-5}"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Please run with sudo: sudo $0 [interval-seconds]"
    exit 1
  fi
}

utun_is_active() {
  netstat -rn -f inet | awk '
    $4 ~ /^utun/ && ($1 == "default" || $1 == "0/1" || $1 == "128.0/1") { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

main() {
  local state last_state=""

  require_root

  echo "Watching utun activity every ${INTERVAL}s"
  while true; do
    if utun_is_active; then
      state="allow"
    else
      state="block"
    fi

    if [[ "$state" != "$last_state" ]]; then
      echo "State changed to ${state}; syncing kill switch"
      "${SCRIPT_DIR}/start-killswitch.sh"
      last_state="$state"
    fi

    sleep "$INTERVAL"
  done
}

main "$@"
