# CLAUDE.md

Development guide for Claude Code.

## Build

```bash
./build.sh
```

Builds C daemon + Swift app + widget, bundles into AWDLControl.app.

## Architecture

| Component | Language | Purpose |
|-----------|----------|---------|
| `awdl_monitor_daemon` | C | AF_ROUTE monitoring, ioctl() control |
| `AWDLControl.app` | Swift | Menu bar UI, daemon management |
| `AWDLControlWidget` | Swift | Control Center widget |

The C daemon does all monitoring (Swift can't use AF_ROUTE efficiently). Swift app controls daemon via launchctl.

## Key Files

- `AWDLMonitorDaemon/awdl_monitor_daemon.c` - Daemon source
- `AWDLControl/AWDLControlApp.swift` - App + menu bar
- `AWDLControl/AWDLMonitor.swift` - Daemon lifecycle

## Version Sync

Keep in sync:
- `awdl_monitor_daemon.c`: `DAEMON_VERSION "1.0.0"`
- `AWDLMonitor.swift`: `expectedDaemonVersion = "1.0.0"`
- `Info.plist`: version strings

## Logs

```bash
# App
log stream --predicate 'subsystem == "com.awdlcontrol.app"'

# Daemon
log show --predicate 'process == "awdl_monitor_daemon"' --last 1h
```

## Test

```bash
pgrep -x awdl_monitor_daemon          # Check running
ifconfig awdl0 | grep flags           # Should show DOWN
```
