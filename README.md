# Kill Switch for macOS

This folder contains the simpler macOS `pf`-based kill switch variant.

Current mode: allow all non-local traffic whenever at least one `utun` route is active; otherwise block non-local traffic on active non-`utun` interfaces.

## Files

- `install-killswitch.sh` installs the `pf` anchor reference, writes local config, and installs a boot-time event-driven LaunchDaemon monitor.
- `killswitch` is the self-contained CLI for `enable`, `disable`, `status`, and `test`.
- `KillSwitchMonitor.swift` is the Swift source for the event-driven PF_ROUTE monitor daemon.
- `uninstall-killswitch.sh` removes the anchor lines from `/etc/pf.conf` and deletes the anchor file.

## Typical usage

Initial setup:

```bash
sudo ./install-killswitch.sh
```

This copies the runtime CLI plus monitor into `/usr/local/libexec/killswitch` as root-owned files and stages the LaunchDaemon plist there. The plist is copied into `/Library/LaunchDaemons` only when you run `sudo killswitch enable`.

It also installs command symlinks into `/usr/local/bin`:

```bash
sudo killswitch enable
sudo killswitch disable
sudo killswitch status
sudo killswitch test
```

Initial install and full uninstall remain separate scripts:

```bash
sudo ./install-killswitch.sh
sudo ./uninstall-killswitch.sh
```

You can run `killswitch status`, `killswitch test`, or `killswitch --help` without `sudo`, but mutating commands like `enable` and `disable` should still be run with `sudo`.

Enable the kill switch daemon and sync it to the current `utun` state:

```bash
sudo killswitch enable
```

Inspect current state:

```bash
sudo killswitch status
sudo killswitch test
```

`killswitch status` starts with a setup health section. Failed checks are shown in red, including missing `pf` anchor references, missing runtime files, unloaded anchors, and missing LaunchDaemon setup.

Disable without uninstalling:

```bash
sudo killswitch disable
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
- The boot watcher runs the root-owned copies from `/usr/local/libexec/killswitch` rather than the workspace files.
- You can also run the installed CLI directly from `/usr/local/libexec/killswitch/killswitch` if you prefer using the system copy.
- Boot-time monitoring now uses a Swift daemon built from `KillSwitchMonitor.swift` and triggered by PF_ROUTE routing-socket events rather than SystemConfiguration notifications or polling.

## Troubleshooting

If this command fails with `pfctl: DIOCGETRULES: Invalid argument`:

```bash
sudo pfctl -a utun-killswitch -sr
```

the anchor file may exist, but `/etc/pf.conf` is not loading it. Reinstall and enable the setup:

```bash
sudo ./install-killswitch.sh
sudo killswitch enable
sudo killswitch status
```

`/etc/pf.conf` must contain both lines:

```pf
anchor "utun-killswitch"
load anchor "utun-killswitch" from "/etc/pf.anchors/utun-killswitch"
```

If `killswitch status` reports a broken setup, the kill switch cannot be trusted to block public traffic until the red failures are fixed.
