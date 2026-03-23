#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(python3 - <<'PY' "${BASH_SOURCE[0]}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

ANCHOR_NAME_DEFAULT="utun-killswitch"
ANCHOR_PATH_DEFAULT="/etc/pf.anchors/${ANCHOR_NAME_DEFAULT}"
PF_CONF_DEFAULT="/etc/pf.conf"
LAUNCHD_LABEL_DEFAULT="com.mxl.killswitch"
LAUNCHD_PLIST_DEFAULT="/Library/LaunchDaemons/${LAUNCHD_LABEL_DEFAULT}.plist"
INSTALL_DIR_DEFAULT="/usr/local/libexec/killswitch"
BIN_PATH_DEFAULT="/usr/local/bin/killswitch"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
  fi
}

run_pfctl_quietly() {
  local cmd_desc="$1"
  shift
  local output

  if ! output="$($@ 2>&1)"; then
    printf '%s\n' "$output" >&2
    echo "Failed to ${cmd_desc}." >&2
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "${file}.bak.$(date +%Y%m%d-%H%M%S)"
  fi
}

remove_anchor_lines() {
  python3 - <<'PY' "$PF_CONF" "$ANCHOR_NAME" "$ANCHOR_PATH"
from pathlib import Path
import sys

path = Path(sys.argv[1])
anchor_name = sys.argv[2]
anchor_path = sys.argv[3]

lines = path.read_text().splitlines()
needle1 = f'anchor "{anchor_name}"'
needle2 = f'load anchor "{anchor_name}" from "{anchor_path}"'

filtered = [line for line in lines if line not in {needle1, needle2}]
path.write_text("\n".join(filtered) + "\n")
PY
}

main() {
  require_root

  ANCHOR_NAME="$ANCHOR_NAME_DEFAULT"
  ANCHOR_PATH="$ANCHOR_PATH_DEFAULT"
  PF_CONF="$PF_CONF_DEFAULT"
  LAUNCHD_LABEL="$LAUNCHD_LABEL_DEFAULT"
  LAUNCHD_PLIST="$LAUNCHD_PLIST_DEFAULT"
  INSTALL_DIR="$INSTALL_DIR_DEFAULT"
  BIN_PATH="$BIN_PATH_DEFAULT"

  backup_file "$LAUNCHD_PLIST"
  backup_file "$PF_CONF"
  backup_file "$ANCHOR_PATH"

  if [[ -f "$LAUNCHD_PLIST" ]]; then
    launchctl unload "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
    rm "$LAUNCHD_PLIST"
    echo "Removed LaunchDaemon ${LAUNCHD_PLIST}"
  else
    echo "LaunchDaemon ${LAUNCHD_PLIST} was already absent"
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "Removed installed runtime scripts ${INSTALL_DIR}"
  else
    echo "Installed runtime directory ${INSTALL_DIR} was already absent"
  fi

  rm -f "$BIN_PATH"
  echo "Removed CLI symlink ${BIN_PATH}"

  if [[ -f "$PF_CONF" ]]; then
    remove_anchor_lines
    echo "Removed anchor lines from ${PF_CONF}"
  fi

  if [[ -f "$ANCHOR_PATH" ]]; then
    rm "$ANCHOR_PATH"
    echo "Removed ${ANCHOR_PATH}"
  else
    echo "Anchor file ${ANCHOR_PATH} was already absent"
  fi

  run_pfctl_quietly "validate pf config" pfctl -nf "$PF_CONF"
  run_pfctl_quietly "reload pf config" pfctl -f "$PF_CONF"

  echo "Kill switch uninstalled from pf."
  echo "Local helper files in ${SCRIPT_DIR} were not removed."
}

main "$@"
