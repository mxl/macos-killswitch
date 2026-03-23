# Kill Switch 2 Workflow

This folder contains the simpler macOS `pf`-based kill switch variant.

Current mode: allow all non-local traffic whenever at least one `utun` route is active; otherwise block non-local traffic on active non-`utun` interfaces.

## Files

- `install-killswitch.sh` installs the `pf` anchor reference, writes local config, and installs a boot-time event-driven LaunchDaemon monitor.
- `start-killswitch.sh` syncs `pf` to the current `utun` state and reloads `pf`.
- `stop-killswitch.sh` disables the anchor contents without uninstalling the setup.
- `status-killswitch.sh` shows config, interfaces, and loaded rules.
- `test-killswitch.sh` validates that the anchor mode matches current `utun` activity.
- `watch-killswitch.sh` is the older polling helper; boot-time monitoring now uses the Swift routing-socket monitor.
- `KillSwitchMonitor.swift` is the Swift source for the event-driven PF_ROUTE monitor daemon.
- `uninstall-killswitch.sh` removes the anchor lines from `/etc/pf.conf` and deletes the anchor file.

## Typical usage

Initial setup:

```bash
sudo ./install-killswitch.sh
```

This also installs `/Library/LaunchDaemons/com.mxl.killswitch2.plist` and copies the runtime commands plus `killswitch.conf` into `/usr/local/libexec/killswitch2` as root-owned files, so the watcher starts at boot and blocks public traffic until a `utun` route becomes active.

`killswitch.conf` is intentionally minimal and only stores the runtime values this variant actually uses: anchor name/path, pf config path, and primary WAN interface.

It also installs command symlinks into `/usr/local/bin`:

```bash
killswitch2-start
killswitch2-stop
killswitch2-status
killswitch2-test
killswitch2-reload
killswitch2-watch
killswitch2-monitor
killswitch2-uninstall
```

Start the kill switch and sync it to the current `utun` state:

```bash
sudo ./start-killswitch.sh
```

Run the legacy polling watcher manually:

```bash
sudo ./watch-killswitch.sh
```

Inspect current state:

```bash
sudo ./status-killswitch.sh
sudo ./test-killswitch.sh
```

Disable without uninstalling:

```bash
sudo ./stop-killswitch.sh
```

Full uninstall from `pf`:

```bash
sudo ./uninstall-killswitch.sh
```

## Notes

- If a `utun` route is active, the anchor switches to allow mode and does not restrict non-local traffic.
- If no `utun` route is active, the anchor switches to block mode and blocks non-local traffic on active non-`utun` interfaces while keeping local traffic allowed.
- This is intentionally looser than the strict `killswitch` variant.
- `uninstall-killswitch.sh` also unloads and removes the LaunchDaemon plist.
- The boot watcher runs the root-owned copies from `/usr/local/libexec/killswitch2` rather than the workspace files.
- You can also run the installed commands directly from `/usr/local/libexec/killswitch2` if you prefer using the system copies.
- Boot-time monitoring now uses a Swift daemon built from `KillSwitchMonitor.swift` and triggered by PF_ROUTE routing-socket events rather than SystemConfiguration notifications or polling.
