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

UNINSTALL_SCRIPT="${SCRIPT_DIR}/uninstall-killswitch.sh"
MONITOR_SOURCE="${SCRIPT_DIR}/KillSwitchMonitor.swift"
CLI_SCRIPT="${SCRIPT_DIR}/killswitch"
LAUNCHD_LABEL="com.mxl.killswitch"
LAUNCHD_PLIST="/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist"
INSTALL_DIR="/usr/local/libexec/killswitch"
BIN_DIR="/usr/local/bin"
BIN_PATH="${BIN_DIR}/killswitch"
INSTALLED_CLI_SCRIPT="${INSTALL_DIR}/killswitch"
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

install_runtime_scripts() {
  mkdir -p "$INSTALL_DIR"
  cp "$CLI_SCRIPT" "$INSTALLED_CLI_SCRIPT"
  cp "$UNINSTALL_SCRIPT" "$INSTALLED_UNINSTALL_SCRIPT"
  cp "$MONITOR_SOURCE" "$INSTALLED_MONITOR_SOURCE"
  swiftc -O -o "$INSTALLED_MONITOR_BIN" "$INSTALLED_MONITOR_SOURCE"
  chown -R root:wheel "$INSTALL_DIR"
  chmod 755 "$INSTALL_DIR"
  chmod 755 \
    "$INSTALLED_CLI_SCRIPT" \
    "$INSTALLED_UNINSTALL_SCRIPT" \
    "$INSTALLED_MONITOR_BIN"
  echo "Installed runtime commands into ${INSTALL_DIR}"
}

seed_placeholder_anchor() {
  cat > "$ANCHOR_PATH" <<'EOF'
# Kill switch installed but not enabled.
EOF
  chmod 600 "$ANCHOR_PATH"
}

install_symlinks() {
  mkdir -p "$BIN_DIR"
  ln -sf "$INSTALLED_CLI_SCRIPT" "$BIN_PATH"
  echo "Installed CLI symlink at ${BIN_PATH}"
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
      <string>${INSTALLED_CLI_SCRIPT}</string>
      <string>__sync</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
      <string>/var/log/killswitch.log</string>

    <key>StandardErrorPath</key>
      <string>/var/log/killswitch.err</string>
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
  install_runtime_scripts
  seed_placeholder_anchor
  install_launchdaemon
  install_symlinks
  pfctl -nf "$PF_CONF"
  pfctl -f "$PF_CONF"
  pfctl -e >/dev/null 2>&1 || true
  echo
  echo "Kill switch files are installed."
  echo "Reinstall later with: sudo ./install-killswitch.sh"
  echo "Uninstall with: sudo ./uninstall-killswitch.sh"
  echo "Enable it with: sudo ${BIN_PATH} enable"
  echo "Disable it with: sudo ${BIN_PATH} disable"
  echo "Installed runtime commands: ${INSTALL_DIR}"
  echo "Installed CLI command: ${BIN_PATH}"
  echo "Installed event-driven monitor: ${INSTALLED_MONITOR_BIN}"
  echo "Boot watcher installed via: ${LAUNCHD_PLIST}"
}

main "$@"
