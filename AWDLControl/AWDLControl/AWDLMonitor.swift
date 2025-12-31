import Foundation
import AppKit
import os.log

/// Unified logger for AWDLMonitor - logs to both Console.app and file
private let log = Logger(subsystem: "com.awdlcontrol.app", category: "Monitor")

/// Signpost for performance measurement
private let signposter = OSSignposter(subsystem: "com.awdlcontrol.app", category: "Performance")

/// Controls the AWDL Monitor Daemon (C daemon using AF_ROUTE sockets)
/// This provides instant response (<1ms) with 0% CPU when idle
///
/// The daemon is a separate C process that monitors interface changes via AF_ROUTE sockets
/// exactly like awdlkiller. On first launch, the app automatically installs the daemon.
class AWDLMonitor {
    static let shared = AWDLMonitor()

    private let daemonLabel = "com.awdlcontrol.daemon"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"
    private let daemonBinaryPath = "/usr/local/bin/awdl_monitor_daemon"

    /// Expected daemon version - should match DAEMON_VERSION in awdl_monitor_daemon.c
    static let expectedDaemonVersion = "1.0.0"

    private var isMonitoring = false

    /// Callback for UI updates
    var onStateChange: (() -> Void)?

    private init() {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("AWDLMonitor initializing...")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Check current state
        let daemonIsInstalled = isDaemonInstalled()
        let daemonIsLoaded = isDaemonLoaded()

        log.info("  Daemon installed: \(daemonIsInstalled)")
        log.info("  Daemon running: \(daemonIsLoaded)")
        log.info("  Daemon binary path: \(self.daemonBinaryPath)")
        log.info("  Daemon plist path: \(self.daemonPlistPath)")

        if daemonIsInstalled {
            if let version = getDaemonVersion() {
                log.info("  Daemon version: \(version)")
                log.info("  Expected version: \(Self.expectedDaemonVersion)")
                log.info("  Version compatible: \(version == Self.expectedDaemonVersion)")
            }
        }

        isMonitoring = daemonIsLoaded

        log.info("  Initial monitoring state: \(self.isMonitoring)")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Public API

    /// Check if daemon is installed (binary and plist exist)
    func isDaemonInstalled() -> Bool {
        let fileManager = FileManager.default
        let binaryExists = fileManager.fileExists(atPath: daemonBinaryPath)
        let plistExists = fileManager.fileExists(atPath: daemonPlistPath)

        log.debug("isDaemonInstalled: binary=\(binaryExists), plist=\(plistExists)")
        return binaryExists && plistExists
    }

    /// Check if monitoring is currently active
    var isMonitoringActive: Bool {
        // Always check actual daemon state
        let running = isDaemonLoaded()
        if running != isMonitoring {
            log.debug("State mismatch detected: cached=\(self.isMonitoring), actual=\(running)")
            isMonitoring = running
        }
        return isMonitoring
    }

    /// Get the installed daemon version
    func getDaemonVersion() -> String? {
        guard FileManager.default.fileExists(atPath: daemonBinaryPath) else {
            log.debug("getDaemonVersion: binary not found")
            return nil
        }

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
            log.debug("getDaemonVersion: \(version ?? "nil")")
            return version
        } catch {
            log.error("getDaemonVersion error: \(error.localizedDescription)")
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

    /// Install daemon and start monitoring - ONE password prompt
    /// This is the main entry point for first-time setup
    func installAndStartMonitoring() {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ installAndStartMonitoring() called                  │")
        log.info("└─────────────────────────────────────────────────────┘")

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("InstallAndStart", id: signpostID)

        // Get bundled daemon resources
        guard let bundlePath = Bundle.main.resourcePath else {
            log.error("Could not find app bundle resources")
            showError("Could not find app bundle resources. Please reinstall the app.")
            signposter.endInterval("InstallAndStart", state)
            return
        }

        let bundledDaemonSource = "\(bundlePath)/AWDLMonitorDaemon"
        let bundledPlistSource = "\(bundlePath)/com.awdlcontrol.daemon.plist"
        let installerScript = "\(bundlePath)/install_daemon.sh"

        log.info("Bundle path: \(bundlePath)")
        log.info("Looking for installer script: \(installerScript)")

        // Check if installer script exists
        guard FileManager.default.fileExists(atPath: installerScript) else {
            log.error("Installer script not found at: \(installerScript)")
            showError("Installer script not found. Please reinstall the app.")
            signposter.endInterval("InstallAndStart", state)
            return
        }

        log.info("Installer script found, requesting admin privileges...")

        // Run installation + start in ONE operation with ONE password
        let installAndStartScript = """
        # Run the installer script
        '\(installerScript)'

        # Start the daemon immediately after installation
        launchctl bootstrap system '\(self.daemonPlistPath)' 2>/dev/null || true

        echo "Installation and startup complete"
        """

        let success = runPrivilegedScript(installAndStartScript, description: "Install and start daemon")

        signposter.endInterval("InstallAndStart", state)

        if success {
            log.info("✅ Installation and startup successful")

            // Wait for daemon to actually start
            if waitForDaemonState(running: true, timeout: 5.0) {
                isMonitoring = true
                AWDLPreferences.shared.isMonitoringEnabled = true
                AWDLPreferences.shared.lastKnownState = "down"
                onStateChange?()

                log.info("✅ Daemon is running, AWDL monitoring active")

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Setup Complete!"
                    alert.informativeText = "AWDLControl is now running.\n\nAWDL is being kept disabled to prevent network latency spikes.\n\nYou can toggle monitoring from the menu bar."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } else {
                log.error("❌ Daemon failed to start after installation")
                showError("Installation completed but daemon failed to start.\n\nTry clicking 'Enable AWDL Monitoring' again.")
            }
        } else {
            log.error("❌ Installation failed or was cancelled")
        }
    }

    /// Start monitoring by loading the LaunchDaemon
    func startMonitoring() {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ startMonitoring() called                            │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Check if daemon is installed
        if !isDaemonInstalled() {
            log.info("Daemon not installed - starting installation flow")
            installAndStartMonitoring()
            return
        }

        // Check daemon version compatibility
        if !isDaemonVersionCompatible() {
            let installedVersion = getDaemonVersion() ?? "unknown"
            log.warning("Version mismatch: installed=\(installedVersion), expected=\(Self.expectedDaemonVersion)")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Daemon Update Required"
                alert.informativeText = "The installed daemon (v\(installedVersion)) needs to be updated to v\(Self.expectedDaemonVersion).\n\nWould you like to update now?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Update Now")
                alert.addButton(withTitle: "Not Now")

                if alert.runModal() == .alertFirstButtonReturn {
                    self.installAndStartMonitoring()
                }
            }
            return
        }

        // Check if daemon is already loaded and running
        if isDaemonLoaded() {
            log.info("Daemon is already running")
            isMonitoring = true
            AWDLPreferences.shared.isMonitoringEnabled = true
            onStateChange?()
            return
        }

        log.info("Loading daemon...")

        // Load the daemon (requires password)
        if loadDaemon() {
            isMonitoring = true
            AWDLPreferences.shared.isMonitoringEnabled = true
            AWDLPreferences.shared.lastKnownState = "down"
            onStateChange?()
            log.info("✅ Daemon loaded successfully")
        } else {
            log.error("❌ Failed to load daemon")
            showError("Failed to start monitoring.\n\nPlease try again or reinstall the daemon.")
        }
    }

    /// Stop monitoring by unloading the LaunchDaemon
    func stopMonitoring() {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ stopMonitoring() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Check if daemon is actually loaded
        if !isDaemonLoaded() {
            log.info("Daemon is not running - nothing to stop")
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"
            onStateChange?()
            return
        }

        log.info("Unloading daemon...")

        if unloadDaemon() {
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"
            onStateChange?()
            log.info("✅ Daemon unloaded - AWDL available for AirDrop/Handoff")
        } else {
            log.error("❌ Failed to unload daemon")
            showError("Failed to stop monitoring.\n\nPlease try again.")
        }
    }

    /// Perform a health check on the daemon
    func performHealthCheck() -> (isHealthy: Bool, message: String) {
        log.info("Performing health check...")

        // Check 1: Is daemon installed?
        guard isDaemonInstalled() else {
            log.info("Health check: Daemon not installed")
            return (false, "Daemon not installed")
        }

        // Check 2: Is version compatible?
        guard isDaemonVersionCompatible() else {
            let version = getDaemonVersion() ?? "unknown"
            log.info("Health check: Version mismatch (\(version) vs \(Self.expectedDaemonVersion))")
            return (false, "Version mismatch: installed \(version), expected \(Self.expectedDaemonVersion)")
        }

        // Check 3: Is daemon process running?
        guard isDaemonLoaded() else {
            log.info("Health check: Daemon not running")
            return (false, "Daemon process not running")
        }

        // Check 4: Check if AWDL is actually down (the daemon's job)
        let awdlStatus = getAWDLStatus()
        log.debug("AWDL status: \(awdlStatus)")

        if awdlStatus.contains("UP") {
            log.warning("Health check: AWDL is UP despite daemon running")
            return (false, "Daemon running but AWDL is UP - daemon may not be functioning")
        }

        let message = "Daemon healthy: v\(getDaemonVersion() ?? "?"), AWDL kept down"
        log.info("Health check: \(message)")
        return (true, message)
    }

    // MARK: - Private Methods

    /// Check if daemon is currently loaded - Check for actual running process
    private func isDaemonLoaded() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "awdl_monitor_daemon"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let isRunning = (task.terminationStatus == 0)
            log.debug("isDaemonLoaded: \(isRunning)")
            return isRunning
        } catch {
            log.error("Error checking daemon process: \(error.localizedDescription)")
            return false
        }
    }

    /// Run a shell script with administrator privileges
    private func runPrivilegedScript(_ script: String, description: String) -> Bool {
        log.info("Running privileged script: \(description)")
        log.debug("Script content:\n\(script)")

        let appleScript = """
        do shell script "\(script.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\n"))" with administrator privileges
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

            log.debug("Script exit code: \(task.terminationStatus)")
            if !output.isEmpty {
                log.debug("Script output: \(output)")
            }

            return task.terminationStatus == 0
        } catch {
            log.error("Script execution error: \(error.localizedDescription)")
            return false
        }
    }

    /// Load the LaunchDaemon
    private func loadDaemon() -> Bool {
        log.info("Loading daemon (requires admin password)...")

        let script = "launchctl bootstrap system '\(daemonPlistPath)'"
        let success = runPrivilegedScript(script, description: "Load daemon")

        if success {
            return waitForDaemonState(running: true, timeout: 3.0)
        }
        return false
    }

    /// Unload the LaunchDaemon
    private func unloadDaemon() -> Bool {
        log.info("Unloading daemon (requires admin password)...")

        let script = "launchctl bootout system/\(daemonLabel)"
        let success = runPrivilegedScript(script, description: "Unload daemon")

        if success {
            return waitForDaemonState(running: false, timeout: 3.0)
        }
        return false
    }

    /// Wait for daemon to reach expected state with timeout
    private func waitForDaemonState(running: Bool, timeout: TimeInterval) -> Bool {
        log.debug("Waiting for daemon state: running=\(running), timeout=\(timeout)s")

        let startTime = Date()
        let checkInterval: TimeInterval = 0.1

        while Date().timeIntervalSince(startTime) < timeout {
            if isDaemonLoaded() == running {
                let elapsed = Date().timeIntervalSince(startTime)
                log.debug("Daemon reached expected state in \(String(format: "%.2f", elapsed))s")
                return true
            }
            Thread.sleep(forTimeInterval: checkInterval)
        }

        log.warning("Timeout waiting for daemon state (expected running=\(running))")
        return isDaemonLoaded() == running
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

            if let flagsLine = output.components(separatedBy: "\n").first(where: { $0.contains("flags=") }) {
                return flagsLine
            }
            return output
        } catch {
            log.error("Error getting AWDL status: \(error.localizedDescription)")
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Show error alert
    private func showError(_ message: String) {
        log.error("Showing error: \(message)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
