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

require_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing ${CONFIG_FILE}. Run sudo ${SCRIPT_DIR}/install-killswitch.sh first."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  WAN_IF="${WAN_IF:-en0}"
}

say() {
  printf '%s\n' "$1"
}

utun_is_active() {
  netstat -rn -f inet | awk '
    $4 ~ /^utun/ && ($1 == "default" || $1 == "0/1" || $1 == "128.0/1") { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

current_mode() {
  if [[ -f "$ANCHOR_PATH" ]]; then
    awk '/^# mode: / { print $3; exit }' "$ANCHOR_PATH"
  fi
}

check_anchor_file() {
  if [[ ! -f "$ANCHOR_PATH" ]]; then
    say "FAIL: Anchor file ${ANCHOR_PATH} does not exist"
    return 1
  fi

  say "PASS: Anchor file exists"
}

check_pf_loaded() {
  if ! sudo pfctl -s info >/dev/null 2>&1; then
    say "FAIL: Unable to read pf status; run this script with sudo"
    return 1
  fi

  say "PASS: pf status is readable"
}

check_mode_matches_state() {
  local mode
  mode="$(current_mode)"

  if utun_is_active; then
    if [[ "$mode" == "allow" ]]; then
      say "PASS: Anchor mode is allow while utun is active"
    else
      say "FAIL: utun is active but anchor mode is ${mode:-unknown}"
      return 1
    fi
  else
    if [[ "$mode" == "block" ]]; then
      say "PASS: Anchor mode is block while no utun route is active"
    else
      say "FAIL: no utun route is active but anchor mode is ${mode:-unknown}"
      return 1
    fi
  fi
}

check_public_behavior() {
  local target output rc
  target="https://1.1.1.1"

  set +e
  output="$(curl -4 -I --silent --show-error --max-time 8 "$target" 2>&1)"
  rc=$?
  set -e

  if utun_is_active; then
    if [[ $rc -eq 0 ]]; then
      say "PASS: Public internet request succeeded while utun is active"
    else
      say "WARN: Public internet request failed even though utun is active"
      say "INFO: curl exit=${rc}: ${output}"
    fi
  else
    if [[ $rc -ne 0 ]]; then
      say "PASS: Public internet request is blocked/fails while no utun is active"
      say "INFO: curl exit=${rc}: ${output}"
    else
      say "FAIL: Public internet request succeeded while no utun is active"
      say "INFO: curl output: ${output}"
      return 1
    fi
  fi
}

main() {
  require_config

  say "Testing simple utun-based kill switch using ${CONFIG_FILE}"
  check_anchor_file
  check_pf_loaded
  check_mode_matches_state
  check_public_behavior
}

main "$@"
