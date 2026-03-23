#!/bin/bash

set -euo pipefail

SCRIPT_PATH="$(python3 - <<'PY' "${BASH_SOURCE[0]}"
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

ANCHOR_NAME="utun-killswitch"
ANCHOR_PATH="/etc/pf.anchors/${ANCHOR_NAME}"
PF_CONF="/etc/pf.conf"

WAN_IF="en0"

CONFIG_FILE="${SCRIPT_DIR}/killswitch.conf"
START_SCRIPT="${SCRIPT_DIR}/start-killswitch.sh"
STOP_SCRIPT="${SCRIPT_DIR}/stop-killswitch.sh"
STATUS_SCRIPT="${SCRIPT_DIR}/status-killswitch.sh"
TEST_SCRIPT="${SCRIPT_DIR}/test-killswitch.sh"
RELOAD_SCRIPT="${SCRIPT_DIR}/reload-killswitch.sh"
WATCH_SCRIPT="${SCRIPT_DIR}/watch-killswitch.sh"
UNINSTALL_SCRIPT="${SCRIPT_DIR}/uninstall-killswitch.sh"
MONITOR_SOURCE="${SCRIPT_DIR}/KillSwitchMonitor.swift"
LAUNCHD_LABEL="com.mxl.killswitch2"
LAUNCHD_PLIST="/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist"
INSTALL_DIR="/usr/local/libexec/killswitch2"
BIN_DIR="/usr/local/bin"
BIN_PREFIX="killswitch2"
INSTALLED_CONFIG_FILE="${INSTALL_DIR}/killswitch.conf"
INSTALLED_START_SCRIPT="${INSTALL_DIR}/start-killswitch.sh"
INSTALLED_STOP_SCRIPT="${INSTALL_DIR}/stop-killswitch.sh"
INSTALLED_STATUS_SCRIPT="${INSTALL_DIR}/status-killswitch.sh"
INSTALLED_TEST_SCRIPT="${INSTALL_DIR}/test-killswitch.sh"
INSTALLED_RELOAD_SCRIPT="${INSTALL_DIR}/reload-killswitch.sh"
INSTALLED_WATCH_SCRIPT="${INSTALL_DIR}/watch-killswitch.sh"
INSTALLED_UNINSTALL_SCRIPT="${INSTALL_DIR}/uninstall-killswitch.sh"
INSTALLED_MONITOR_SOURCE="${INSTALL_DIR}/KillSwitchMonitor.swift"
INSTALLED_MONITOR_BIN="${INSTALL_DIR}/killswitch-monitor"

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Please run with sudo: sudo $0"
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "${file}.bak.$(date +%Y%m%d-%H%M%S)"
  fi
}

ensure_anchor_lines() {
  if ! grep -Fq "anchor \"${ANCHOR_NAME}\"" "$PF_CONF"; then
    printf '\nanchor "%s"\nload anchor "%s" from "%s"\n' \
      "$ANCHOR_NAME" "$ANCHOR_NAME" "$ANCHOR_PATH" >> "$PF_CONF"
    echo "Added anchor to ${PF_CONF}"
  else
    echo "Anchor already present in ${PF_CONF}"
  fi
}

write_config() {
  cat > "$CONFIG_FILE" <<EOF
ANCHOR_NAME="${ANCHOR_NAME}"
ANCHOR_PATH="${ANCHOR_PATH}"
PF_CONF="${PF_CONF}"
WAN_IF="${WAN_IF}"
EOF
  chmod 600 "$CONFIG_FILE"
  echo "Wrote ${CONFIG_FILE}"
}

install_runtime_scripts() {
  mkdir -p "$INSTALL_DIR"
  cp "$CONFIG_FILE" "$INSTALLED_CONFIG_FILE"
  cp "$START_SCRIPT" "$INSTALLED_START_SCRIPT"
  cp "$STOP_SCRIPT" "$INSTALLED_STOP_SCRIPT"
  cp "$STATUS_SCRIPT" "$INSTALLED_STATUS_SCRIPT"
  cp "$TEST_SCRIPT" "$INSTALLED_TEST_SCRIPT"
  cp "$RELOAD_SCRIPT" "$INSTALLED_RELOAD_SCRIPT"
  cp "$WATCH_SCRIPT" "$INSTALLED_WATCH_SCRIPT"
  cp "$UNINSTALL_SCRIPT" "$INSTALLED_UNINSTALL_SCRIPT"
  cp "$MONITOR_SOURCE" "$INSTALLED_MONITOR_SOURCE"
  swiftc -O -o "$INSTALLED_MONITOR_BIN" "$INSTALLED_MONITOR_SOURCE"
  chown -R root:wheel "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR"
  chmod 600 "$INSTALLED_CONFIG_FILE"
  chmod 700 \
    "$INSTALLED_START_SCRIPT" \
    "$INSTALLED_STOP_SCRIPT" \
    "$INSTALLED_STATUS_SCRIPT" \
    "$INSTALLED_TEST_SCRIPT" \
    "$INSTALLED_RELOAD_SCRIPT" \
    "$INSTALLED_WATCH_SCRIPT" \
    "$INSTALLED_UNINSTALL_SCRIPT" \
    "$INSTALLED_MONITOR_BIN"
  echo "Installed runtime commands into ${INSTALL_DIR}"
}

install_symlinks() {
  mkdir -p "$BIN_DIR"
  ln -sf "$INSTALLED_START_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-start"
  ln -sf "$INSTALLED_STOP_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-stop"
  ln -sf "$INSTALLED_STATUS_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-status"
  ln -sf "$INSTALLED_TEST_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-test"
  ln -sf "$INSTALLED_RELOAD_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-reload"
  ln -sf "$INSTALLED_WATCH_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-watch"
  ln -sf "$INSTALLED_UNINSTALL_SCRIPT" "${BIN_DIR}/${BIN_PREFIX}-uninstall"
  ln -sf "$INSTALLED_MONITOR_BIN" "${BIN_DIR}/${BIN_PREFIX}-monitor"
  echo "Installed command symlinks into ${BIN_DIR}"
}

install_launchdaemon() {
  backup_file "$LAUNCHD_PLIST"

  cat > "$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LAUNCHD_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
      <string>${INSTALLED_MONITOR_BIN}</string>
      <string>${INSTALLED_START_SCRIPT}</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/var/log/killswitch2.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/killswitch2.err</string>
  </dict>
</plist>
EOF

  chown root:wheel "$LAUNCHD_PLIST"
  chmod 644 "$LAUNCHD_PLIST"

  launchctl unload "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
  launchctl load -w "$LAUNCHD_PLIST"

  echo "Installed LaunchDaemon ${LAUNCHD_LABEL}"
}

main() {
  require_root
  backup_file "$PF_CONF"
  backup_file "$ANCHOR_PATH"
  ensure_anchor_lines
  write_config
  install_runtime_scripts
  install_symlinks
  install_launchdaemon
  pfctl -nf "$PF_CONF"
  pfctl -f "$PF_CONF"
  pfctl -e >/dev/null 2>&1 || true
  echo
  echo "Kill switch files are installed."
  echo "Start it with: sudo ${START_SCRIPT}"
  echo "Stop it with: sudo ${STOP_SCRIPT}"
  echo "Installed runtime commands: ${INSTALL_DIR}"
  echo "Installed command symlinks: ${BIN_DIR}/${BIN_PREFIX}-*"
  echo "Installed event-driven monitor: ${INSTALLED_MONITOR_BIN}"
  echo "Boot watcher installed via: ${LAUNCHD_PLIST}"
}

main "$@"
