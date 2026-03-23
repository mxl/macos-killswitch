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
LAUNCHD_LABEL_DEFAULT="com.mxl.killswitch2"
LAUNCHD_PLIST_DEFAULT="/Library/LaunchDaemons/${LAUNCHD_LABEL_DEFAULT}.plist"

require_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Missing ${CONFIG_FILE}. Run sudo ${SCRIPT_DIR}/install-killswitch.sh first."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  WAN_IF="${WAN_IF:-en0}"
  LAUNCHD_LABEL="${LAUNCHD_LABEL:-$LAUNCHD_LABEL_DEFAULT}"
  LAUNCHD_PLIST="${LAUNCHD_PLIST:-$LAUNCHD_PLIST_DEFAULT}"
}

print_header() {
  printf '\n== %s ==\n' "$1"
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

main() {
  local mode

  require_config

  print_header "Config"
  echo "Anchor: ${ANCHOR_NAME}"
  echo "Anchor path: ${ANCHOR_PATH}"
  echo "PF config: ${PF_CONF}"
  echo "Primary WAN interface: ${WAN_IF}"

  print_header "utun State"
  if utun_is_active; then
    echo "Active utun route detected: yes"
  else
    echo "Active utun route detected: no"
  fi
  mode="$(current_mode)"
  echo "Anchor mode: ${mode:-unknown}"

  print_header "Detected utun Interfaces"
  /sbin/ifconfig | awk '/^utun[0-9]+:/{sub(":","",$1); print $1}' || true

  print_header "Detected Active Non-utun Interfaces"
  /sbin/ifconfig -l | tr ' ' '\n' | while read -r iface; do
    [[ -z "$iface" ]] && continue
    case "$iface" in
      lo0|utun*|gif*|stf*|anpi*|awdl*|llw*|ap*|bridge*)
        continue
        ;;
    esac
    if /sbin/ifconfig "$iface" 2>/dev/null | grep -q 'status: active'; then
      echo "$iface"
    fi
  done

  print_header "PF Status"
  if sudo pfctl -s info >/dev/null 2>&1; then
    sudo pfctl -s info | sed -n '1,20p'
  else
    echo "Unable to read pf status. Try running this script with sudo."
  fi

  print_header "Monitor Status"
  echo "LaunchDaemon plist: ${LAUNCHD_PLIST}"
  if [[ -f "$LAUNCHD_PLIST" ]]; then
    echo "LaunchDaemon plist present: yes"
  else
    echo "LaunchDaemon plist present: no"
  fi
  if sudo launchctl print "system/${LAUNCHD_LABEL}" >/tmp/killswitch2-launchctl.$$ 2>/tmp/killswitch2-launchctl-err.$$; then
    awk '
      /state =/ || /pid =/ || /last exit code =/ || /path =/ || /program =/ || /arguments =/ {
        print
      }
    ' /tmp/killswitch2-launchctl.$$
  else
    echo "LaunchDaemon not loaded or not readable."
    if [[ -s /tmp/killswitch2-launchctl-err.$$ ]]; then
      cat /tmp/killswitch2-launchctl-err.$$
    fi
  fi
  rm -f /tmp/killswitch2-launchctl.$$ /tmp/killswitch2-launchctl-err.$$

  print_header "Anchor File"
  if [[ -f "$ANCHOR_PATH" ]]; then
    cat "$ANCHOR_PATH"
  else
    echo "Anchor file does not exist."
  fi

  print_header "Loaded Rules"
  if sudo pfctl -a "$ANCHOR_NAME" -sr >/dev/null 2>&1; then
    sudo pfctl -a "$ANCHOR_NAME" -sr
  else
    echo "Unable to read loaded anchor rules. Try running this script with sudo."
  fi
}

main "$@"
