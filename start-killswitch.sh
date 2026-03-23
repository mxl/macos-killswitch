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
  WAN_IF="${WAN_IF:-en0}"
}

detect_protected_interfaces() {
  local iface
  local -a protected=()

  while read -r iface; do
    [[ -z "$iface" ]] && continue
    case "$iface" in
      lo0|utun*|gif*|stf*|anpi*|awdl*|llw*|ap*|bridge*)
        continue
        ;;
    esac

    if ifconfig "$iface" 2>/dev/null | grep -q 'status: active'; then
      protected+=("$iface")
    fi
  done < <(ifconfig -l | tr ' ' '\n')

  if [[ ${#protected[@]} -eq 0 ]]; then
    echo "Could not detect any active non-utun interfaces to protect."
    exit 1
  fi

  printf '%s\n' "${protected[@]}"
}

utun_is_active() {
  netstat -rn -f inet | awk '
    $4 ~ /^utun/ && ($1 == "default" || $1 == "0/1" || $1 == "128.0/1") { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

build_local_rules() {
  local iface ip mask cidr
  local -a interfaces=("$@")

  for iface in "${interfaces[@]}"; do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    mask="$(ipconfig getoption "$iface" subnet_mask 2>/dev/null || true)"

    if [[ -n "$ip" && -n "$mask" ]]; then
      cidr="$(python3 - <<'PY' "$ip" "$mask"
import ipaddress
import sys
iface = ipaddress.IPv4Interface(f"{sys.argv[1]}/{sys.argv[2]}")
print(iface.network.with_prefixlen)
PY
)"
      printf 'pass out quick on %s to { 127.0.0.0/8, 169.254.0.0/16, %s } keep state\n' "$iface" "$cidr"
    else
      printf 'pass out quick on %s to { 127.0.0.0/8, 169.254.0.0/16 } keep state\n' "$iface"
    fi
  done
}

write_allow_anchor() {
  cat > "$ANCHOR_PATH" <<'EOF'
# mode: allow
# At least one utun interface is active, so pf does not restrict non-local traffic.
EOF
  chmod 600 "$ANCHOR_PATH"
}

write_block_anchor() {
  local -a protected_ifaces=("$@")

  cat > "$ANCHOR_PATH" <<'EOF'
# mode: block
set block-policy drop
set skip on lo0
EOF

  build_local_rules "${protected_ifaces[@]}" >> "$ANCHOR_PATH"

  for iface in "${protected_ifaces[@]}"; do
    printf 'block drop out quick on %s all\n' "$iface" >> "$ANCHOR_PATH"
  done

  chmod 600 "$ANCHOR_PATH"
}

main() {
  local iface mode
  local -a protected_ifaces=()

  require_root
  require_config

  while read -r iface; do
    [[ -z "$iface" ]] && continue
    protected_ifaces+=("$iface")
  done < <(detect_protected_interfaces)

  if utun_is_active; then
    mode="allow"
    write_allow_anchor
  else
    mode="block"
    write_block_anchor "${protected_ifaces[@]}"
  fi

  pfctl -nf "$PF_CONF"
  pfctl -f "$PF_CONF"
  pfctl -e >/dev/null 2>&1 || true

  echo "Kill switch synced."
  echo "Mode: ${mode}"
  echo "Protected non-utun interfaces: ${protected_ifaces[*]}"
  if [[ "$mode" == "allow" ]]; then
    echo "An active utun route was detected, so non-local traffic is allowed."
  else
    echo "No active utun route was detected, so non-local traffic is blocked on protected interfaces."
  fi
}

main "$@"
