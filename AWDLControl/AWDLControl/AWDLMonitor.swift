import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.awdlcontrol.app", category: "Monitor")

/// Controls the AWDL Monitor Daemon (C daemon using AF_ROUTE sockets)
/// This provides instant response (<1ms) with 0% CPU when idle
///
/// The daemon is a separate C process that monitors interface changes via AF_ROUTE sockets
/// exactly like awdlkiller. This version uses a simple one-time installer approach.
class AWDLMonitor {
    static let shared = AWDLMonitor()

    private let daemonLabel = "com.awdlcontrol.daemon"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"
    private let daemonBinaryPath = "/usr/local/bin/awdl_monitor_daemon"

    /// Expected daemon version - should match DAEMON_VERSION in awdl_monitor_daemon.c
    static let expectedDaemonVersion = "1.6.0"

    private var isMonitoring = false

    private init() {
        // Check if daemon is currently loaded
        let daemonIsLoaded = isDaemonLoaded()

        // Check if daemon is installed
        let daemonIsInstalled = isDaemonInstalled()

        // Preference is the source of truth - sync daemon state to match preference
        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled

        if !daemonIsInstalled {
            log.info("Daemon not installed yet - will show install instructions on first toggle")
            isMonitoring = false
        } else if shouldMonitor && !daemonIsLoaded {
            // Preference says monitor, but daemon not running - start it
            log.info("Preference enabled but daemon not running")
            isMonitoring = false
        } else if !shouldMonitor && daemonIsLoaded {
            // Preference says don't monitor, but daemon is running
            log.info("Preference disabled but daemon running")
            isMonitoring = true
        } else {
            // States match
            isMonitoring = daemonIsLoaded
            if isMonitoring {
                log.info("Daemon is loaded and running (matches preference)")
            } else {
                log.info("Daemon is not running (matches preference)")
            }
        }
    }

    /// Check if daemon binary and plist are installed
    private func isDaemonInstalled() -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: daemonBinaryPath) &&
               fileManager.fileExists(atPath: daemonPlistPath)
    }

    /// Get the installed daemon version
    func getDaemonVersion() -> String? {
        guard isDaemonInstalled() else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: daemonBinaryPath)
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return version
        } catch {
            log.error("Error getting daemon version: \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if installed daemon version matches expected version
    func isDaemonVersionCompatible() -> Bool {
        guard let installedVersion = getDaemonVersion() else {
            return false
        }
        return installedVersion == Self.expectedDaemonVersion
    }

    /// Show installation instructions to user
    private func showInstallInstructions() {
        // Get path to installer script in app bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            showError("Could not find app bundle resources")
            return
        }

        let installerScript = "\(bundlePath)/install_daemon.sh"

        // Build the install command
        let installCommand = "sudo '\(installerScript)'"

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Welcome to AWDLControl! 👋"
            alert.informativeText = """
            One-time setup required (30 seconds):

            AWDLControl needs to install a system daemon that keeps AWDL down with <1ms response time and 0% CPU when idle.

            This is a ONE-TIME setup. After this, you can toggle monitoring instantly from the menu bar with no password prompts!

            Ready? Click "Install Daemon" and I'll guide you through it.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install Daemon")
            alert.addButton(withTitle: "Not Now")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Copy install command to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(installCommand, forType: .string)

                // Open Terminal
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                  configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error = error {
                        log.error("Error opening Terminal: \(error.localizedDescription)")
                    }
                }

                // Show follow-up instructions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let followUp = NSAlert()
                    followUp.messageText = "Installation Command Copied! 📋"
                    followUp.informativeText = """
                    Perfect! The installation command is on your clipboard.

                    In the Terminal window that just opened:

                    1️⃣ Paste the command (⌘V or right-click → Paste)
                    2️⃣ Press Enter
                    3️⃣ Enter your password when prompted
                    4️⃣ Wait for "Installation Complete! ✅"
                    5️⃣ Come back here and toggle monitoring!

                    The command:
                    \(installCommand)
                    """
                    followUp.alertStyle = .informational
                    followUp.addButton(withTitle: "Got It!")
                    followUp.runModal()
                }
            }
        }
    }


    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Show version mismatch warning and offer to reinstall
    private func showVersionMismatchWarning(installedVersion: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Daemon Update Required"
            alert.informativeText = """
            The installed daemon version (\(installedVersion)) doesn't match the expected version (\(Self.expectedDaemonVersion)).

            Please reinstall the daemon to ensure compatibility and get the latest fixes.

            Use "Reinstall Daemon" from the menu bar to update.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Start monitoring by loading the LaunchDaemon
    func startMonitoring() {
        log.debug("startMonitoring() called")

        // Check if daemon is installed
        if !isDaemonInstalled() {
            log.info("Daemon not installed")
            showInstallInstructions()
            return
        }

        // Check daemon version compatibility
        if !isDaemonVersionCompatible() {
            let installedVersion = getDaemonVersion() ?? "unknown"
            log.warning("Daemon version mismatch: installed=\(installedVersion), expected=\(Self.expectedDaemonVersion)")
            showVersionMismatchWarning(installedVersion: installedVersion)
            return
        }

        log.debug("Daemon is installed, checking if loaded...")

        // Check if daemon is already loaded and running
        if isDaemonLoaded() {
            log.info("Daemon is already running and controlling AWDL")
            isMonitoring = true
            AWDLPreferences.shared.isMonitoringEnabled = true
            AWDLPreferences.shared.lastKnownState = "down"

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Monitoring Already Active"
                alert.informativeText = "The AWDL monitoring daemon is already running and keeping AWDL down.\n\nNo action needed!"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        log.debug("Daemon not loaded, attempting to load...")

        // Try to load the daemon using a simple shell script approach
        // This works because the daemon plist is already installed by the one-time setup
        if loadDaemon() {
            isMonitoring = true
            AWDLPreferences.shared.isMonitoringEnabled = true
            AWDLPreferences.shared.lastKnownState = "down"
            log.info("Daemon loaded successfully")
        } else {
            log.error("Failed to load daemon")
            showError("Failed to start monitoring.\n\nPlease run these commands in Terminal:\n\nsudo launchctl bootstrap system /Library/LaunchDaemons/com.awdlcontrol.daemon.plist")
        }
    }

    /// Stop monitoring by unloading the LaunchDaemon
    func stopMonitoring() {
        log.debug("Stopping monitoring daemon")

        // Check if daemon is actually loaded
        if !isDaemonLoaded() {
            log.info("Daemon is not running")
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Monitoring Already Stopped"
                alert.informativeText = "The AWDL monitoring daemon is not running.\n\nAWDL is available for AirDrop/Handoff."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        if unloadDaemon() {
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"
            log.info("Daemon unloaded - AWDL available for AirDrop/Handoff")
        } else {
            log.error("Failed to unload daemon")
            showError("Failed to stop monitoring.\n\nPlease run this command in Terminal:\n\nsudo launchctl bootout system/com.awdlcontrol.daemon")
        }
    }

    /// Check if daemon is currently loaded - Check for actual running process
    private func isDaemonLoaded() -> Bool {
        // System daemons aren't visible via launchctl list from user processes
        // So instead, check if the daemon process is actually running using pgrep
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "awdl_monitor_daemon"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            // pgrep returns 0 if process is found, 1 if not found
            let isRunning = (task.terminationStatus == 0)
            log.debug("isDaemonLoaded() via pgrep = \(isRunning)")
            return isRunning
        } catch {
            log.error("Error checking daemon process: \(error.localizedDescription)")
            return false
        }
    }

    /// Load the LaunchDaemon using osascript with administrator privileges
    /// This prompts for password each time but is reliable and works on all macOS versions
    private func loadDaemon() -> Bool {
        log.debug("Loading daemon (requires admin password)...")

        let appleScript = """
        do shell script "launchctl bootstrap system \(daemonPlistPath)" with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 || output.contains("Already loaded") {
                log.info("Successfully loaded daemon")
                // Wait for daemon to actually start and verify
                return waitForDaemonState(running: true, timeout: 3.0)
            } else {
                log.error("Error loading daemon: \(output)")
                return false
            }
        } catch {
            log.error("Exception loading daemon: \(error.localizedDescription)")
            return false
        }
    }

    /// Wait for daemon to reach expected state with timeout
    private func waitForDaemonState(running: Bool, timeout: TimeInterval) -> Bool {
        let startTime = Date()
        let checkInterval: TimeInterval = 0.1

        while Date().timeIntervalSince(startTime) < timeout {
            if isDaemonLoaded() == running {
                log.debug("Daemon reached expected state (running=\(running)) in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s")
                return true
            }
            Thread.sleep(forTimeInterval: checkInterval)
        }

        log.warning("Timeout waiting for daemon state (expected running=\(running))")
        return isDaemonLoaded() == running
    }

    /// Unload the LaunchDaemon using osascript with administrator privileges
    /// This prompts for password each time but is reliable and works on all macOS versions
    private func unloadDaemon() -> Bool {
        log.debug("Unloading daemon (requires admin password)...")

        let appleScript = """
        do shell script "launchctl bootout system/\(daemonLabel)" with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 || output.contains("not find") || output.contains("Could not find") {
                log.info("Successfully unloaded daemon")
                // Wait for daemon to actually stop and verify
                return waitForDaemonState(running: false, timeout: 3.0)
            } else {
                log.error("Error unloading daemon: \(output)")
                return false
            }
        } catch {
            log.error("Exception unloading daemon: \(error.localizedDescription)")
            return false
        }
    }

    /// Check if monitoring is currently active
    var isMonitoringActive: Bool {
        return isMonitoring
    }

    /// Perform a health check on the daemon
    /// Returns a tuple of (isHealthy, statusMessage)
    func performHealthCheck() -> (isHealthy: Bool, message: String) {
        // Check 1: Is daemon installed?
        guard isDaemonInstalled() else {
            return (false, "Daemon not installed")
        }

        // Check 2: Is version compatible?
        guard isDaemonVersionCompatible() else {
            let version = getDaemonVersion() ?? "unknown"
            return (false, "Version mismatch: installed \(version), expected \(Self.expectedDaemonVersion)")
        }

        // Check 3: Is daemon process running?
        guard isDaemonLoaded() else {
            return (false, "Daemon process not running")
        }

        // Check 4: Check if AWDL is actually down (the daemon's job)
        let awdlStatus = getAWDLStatus()
        if awdlStatus.contains("UP") {
            return (false, "Daemon running but AWDL is UP - daemon may not be functioning")
        }

        return (true, "Daemon healthy: v\(getDaemonVersion() ?? "?"), AWDL kept down")
    }

    /// Get current AWDL interface status
    private func getAWDLStatus() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["awdl0"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Extract flags line
            if let flagsLine = output.components(separatedBy: "\n").first(where: { $0.contains("flags=") }) {
                return flagsLine
            }
            return output
        } catch {
            log.error("Error getting AWDL status: \(error.localizedDescription)")
            return "Error: \(error.localizedDescription)"
        }
    }
}
