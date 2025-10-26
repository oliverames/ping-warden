import Foundation

/// Controls the AWDL Monitor Daemon (C daemon using AF_ROUTE sockets)
/// This provides instant response (<1ms) with 0% CPU when idle
///
/// The daemon is a separate C process that monitors interface changes via AF_ROUTE sockets
/// exactly like awdlkiller. The Swift app just starts/stops it via launchctl.
class AWDLMonitor {
    static let shared = AWDLMonitor()

    private let daemonLabel = "com.awdlcontrol.daemon"
    private let daemonPlistPath = "/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"
    private let manager = AWDLManager.shared

    private var isMonitoring = false

    private init() {
        // Check if daemon is currently loaded
        isMonitoring = isDaemonLoaded()

        // Sync preferences with actual daemon state
        AWDLPreferences.shared.isMonitoringEnabled = isMonitoring

        if isMonitoring {
            print("AWDLMonitor: Daemon is loaded and running")
        }
    }

    /// Start monitoring by loading the LaunchDaemon
    func startMonitoring() {
        guard !isMonitoring else {
            print("AWDLMonitor: Daemon already running")
            return
        }

        print("AWDLMonitor: Starting monitoring daemon")

        // Load the LaunchDaemon (it will bring AWDL down automatically on startup)
        if loadDaemon() {
            isMonitoring = true
            AWDLPreferences.shared.isMonitoringEnabled = true
            AWDLPreferences.shared.lastKnownState = "down"
            print("AWDLMonitor: ✅ Daemon loaded and monitoring started")
        } else {
            print("AWDLMonitor: ❌ Failed to load daemon")
        }
    }

    /// Stop monitoring by unloading the LaunchDaemon
    /// Note: AWDL will be brought up automatically by macOS when needed (AirDrop, Handoff, etc.)
    func stopMonitoring() {
        guard isMonitoring else {
            print("AWDLMonitor: Daemon not running")
            return
        }

        print("AWDLMonitor: Stopping monitoring daemon")

        // Unload the LaunchDaemon
        if unloadDaemon() {
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            print("AWDLMonitor: ✅ Daemon unloaded - AWDL will be available for AirDrop/Handoff when needed")
        } else {
            print("AWDLMonitor: ❌ Failed to unload daemon")
        }
    }

    /// Check if daemon is currently loaded
    private func isDaemonLoaded() -> Bool {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", daemonLabel]
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Load the LaunchDaemon (requires root privileges)
    private func loadDaemon() -> Bool {
        // Check if plist exists
        guard FileManager.default.fileExists(atPath: daemonPlistPath) else {
            print("AWDLMonitor: Daemon plist not found at \(daemonPlistPath)")
            print("AWDLMonitor: Please run install_daemon.sh first")
            return false
        }

        // Use osascript to run launchctl with admin privileges
        let script = """
        do shell script "launchctl load '\(daemonPlistPath)'" with administrator privileges
        """

        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("AWDLMonitor: Error loading daemon: \(output)")
                return false
            }

            print("AWDLMonitor: Successfully loaded daemon with admin privileges")
            return true
        } catch {
            print("AWDLMonitor: Error loading daemon: \(error)")
            return false
        }
    }

    /// Unload the LaunchDaemon (requires root privileges)
    private func unloadDaemon() -> Bool {
        // Use osascript to run launchctl with admin privileges
        let script = """
        do shell script "launchctl unload '\(daemonPlistPath)'" with administrator privileges
        """

        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("AWDLMonitor: Error unloading daemon: \(output)")
                return false
            }

            print("AWDLMonitor: Successfully unloaded daemon with admin privileges")
            return true
        } catch {
            print("AWDLMonitor: Error unloading daemon: \(error)")
            return false
        }
    }

    /// Check if monitoring is currently active
    var isMonitoringActive: Bool {
        return isMonitoring
    }
}
