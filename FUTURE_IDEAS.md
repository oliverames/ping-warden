# Future Ideas and Experiments

This document captures ideas for future development that have been discussed but not yet implemented.

## Password Prompt Reduction

### Current Behavior
Password prompts (via `osascript` with `administrator privileges`) are required for:
- **Initial install**: Writing daemon to `/usr/local/bin/` and plist to `/Library/LaunchDaemons/`
- **Every start**: `launchctl bootstrap system/...` requires root
- **Every stop**: `launchctl bootout system/...` requires root
- **Reinstall/Uninstall**: Same privileged operations

### Mitigation (Current)
Enabling "Launch at Login" reduces password prompts because:
1. The daemon starts automatically at boot (LaunchDaemon)
2. The app starts automatically at login
3. If daemon is already running, toggling just sends signals (no launchctl needed)

### Future Options Explored

#### Option 1: Daemon Always Runs + IPC Control
**Concept**: Daemon starts at boot and runs continuously. App sends enable/disable commands via Unix socket or control file instead of starting/stopping the daemon process.

**Pros:**
- Password only at initial install
- Instant toggle response
- Works with Control Center widget without password

**Cons:**
- Daemon uses resources even when disabled
- More complex daemon code
- Security: any process could send commands

**Implementation**: ~2-3 hours
- Modify daemon to watch control file + AF_ROUTE socket
- Modify AWDLMonitor.swift to write control file

#### Option 2: SMAppService Privileged Helper (XPC)
**Concept**: Modern Apple approach using XPC for privileged operations.

**Pros:**
- Apple's recommended pattern
- Secure (code-signed verification)
- Password only at helper installation

**Cons:**
- Requires Developer ID code signing
- More complex architecture
- XPC learning curve

**Implementation**: ~1-2 days

#### Option 3: Control File Approach (Simplest)
**Concept**: Daemon watches a control file (e.g., `/var/run/awdl_control`).

```c
// Daemon pseudocode
while (1) {
    poll(fds, 2, -1);  // AF_ROUTE + control file
    if (control_file_changed) {
        enabled = read_control_file();
    }
    if (enabled && awdl_came_up) {
        disable_awdl();
    }
}
```

**Pros:**
- Minimal daemon changes (~50 lines)
- No code signing requirements
- Password only at install

**Cons:**
- Control file permissions matter
- Less secure than XPC

**Implementation**: ~2-3 hours

### Recommendation
Option 3 (Control File) offers the best balance of simplicity and user experience improvement. It requires minimal C code changes and eliminates ongoing password prompts after initial setup.

---

## Other Future Ideas

### Control Center Widget Improvements
- Investigate why widget may not appear in Control Center
- Test on physical macOS 26 device
- Consider adding widget configuration options

### Game Mode Detection Enhancements
- Use actual macOS Game Mode API if/when available
- Add configurable list of "game" applications
- Reduce polling interval or use event-based detection

### UI/UX Improvements
- Add onboarding tutorial
- Localization support
- Keyboard shortcuts for common actions
- Touch Bar support (if applicable)

---

*Last updated: 2025*
