import Foundation
import AppKit
import ServiceManagement
import os.log

/// Unified logger for AWDLMonitor - logs to both Console.app and file
private let log = Logger(subsystem: "com.awdlcontrol.app", category: "Monitor")

/// Signpost for performance measurement
private let signposter = OSSignposter(subsystem: "com.awdlcontrol.app", category: "Performance")

/// Controls the AWDL helper daemon via SMAppService and XPC
/// In v2.0, the helper runs as a bundled LaunchDaemon registered via SMAppService
/// No more password prompts - just one-time system approval
///
/// Architecture (v2.0):
/// - Helper binary bundled in Contents/MacOS/AWDLControlHelper
/// - Plist bundled in Contents/Library/LaunchDaemons/com.awdlcontrol.helper.plist
/// - Communication via XPC (com.awdlcontrol.xpc.helper)
/// - Helper exits when app quits (via XPC connection invalidation)
class AWDLMonitor {
    static let shared = AWDLMonitor()

    /// XPC service name - must match MachServices key in plist
    private let xpcServiceName = "com.awdlcontrol.xpc.helper"

    /// Plist filename for SMAppService - must match file in Contents/Library/LaunchDaemons/
    private let helperPlistName = "com.awdlcontrol.helper.plist"

    /// SMAppService instance for the helper daemon
    private lazy var helperService: SMAppService = {
        return SMAppService.daemon(plistName: helperPlistName)
    }()

    /// XPC connection to the helper
    private var xpcConnection: NSXPCConnection?

    /// Lock for thread-safe access to isMonitoring flag
    private let stateLock = NSLock()
    private var _isMonitoring = false

    /// Thread-safe access to monitoring state
    private var isMonitoring: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isMonitoring
        }
        set {
            stateLock.lock()
            _isMonitoring = newValue
            stateLock.unlock()
        }
    }

    /// Callback for UI updates
    var onStateChange: (() -> Void)?

    /// Timer for polling registration status
    private var registrationTimer: Timer?

    private init() {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("AWDLMonitor v2.0 initializing (SMAppService + XPC)...")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let status = helperService.status
        log.info("  Helper service status: \(self.statusDescription(status))")
        log.info("  XPC service name: \(self.xpcServiceName)")
        log.info("  Helper plist: \(self.helperPlistName)")

        // If helper is already registered, connect to it
        if status == .enabled {
            log.info("  Helper already enabled, connecting XPC...")
            connectXPC()

            // Check if we should restore monitoring state
            if AWDLPreferences.shared.isMonitoringEnabled {
                log.info("  Restoring monitoring state from preferences")
                startMonitoring()
            }
        }

        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Public API

    /// Check if helper is registered with SMAppService
    var isHelperRegistered: Bool {
        return helperService.status == .enabled
    }

    /// Check if helper needs system approval (user denied or not yet approved)
    var needsApproval: Bool {
        return helperService.status == .requiresApproval
    }

    /// Current registration status
    var registrationStatus: SMAppService.Status {
        return helperService.status
    }

    /// Check if monitoring is currently active
    var isMonitoringActive: Bool {
        return isMonitoring && xpcConnection != nil
    }

    /// Register helper with SMAppService
    /// This triggers a one-time system approval prompt (not a password dialog)
    func registerHelper(completion: ((Bool) -> Void)? = nil) {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ registerHelper() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("RegisterHelper", id: signpostID)

        let currentStatus = helperService.status
        log.info("Current status: \(self.statusDescription(currentStatus))")

        switch currentStatus {
        case .enabled:
            log.info("Helper already enabled")
            signposter.endInterval("RegisterHelper", state)
            connectXPC()
            completion?(true)
            return

        case .requiresApproval:
            log.info("Helper requires approval - opening System Settings")
            SMAppService.openSystemSettingsLoginItems()
            startPollingForRegistration(completion: completion)
            signposter.endInterval("RegisterHelper", state)
            return

        case .notRegistered, .notFound:
            log.info("Registering helper with SMAppService...")
            do {
                try helperService.register()
                log.info("Registration request submitted")
                // Start polling for approval
                startPollingForRegistration(completion: completion)
            } catch {
                log.error("Registration failed: \(error.localizedDescription)")
                signposter.endInterval("RegisterHelper", state)

                DispatchQueue.main.async {
                    self.showError("Failed to register helper.\n\nError: \(error.localizedDescription)")
                }
                completion?(false)
            }

        @unknown default:
            log.error("Unknown helper status: \(String(describing: currentStatus))")
            signposter.endInterval("RegisterHelper", state)
            completion?(false)
        }
    }

    /// Start monitoring - sends command to helper via XPC
    func startMonitoring() {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ startMonitoring() called                            │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Check if helper is registered
        guard isHelperRegistered else {
            log.info("Helper not registered - starting registration flow")
            registerHelper { success in
                if success {
                    self.startMonitoring()
                }
            }
            return
        }

        // Ensure XPC connection
        if xpcConnection == nil {
            connectXPC()
        }

        // Send command to disable AWDL
        guard let proxy = getHelperProxy() else {
            log.error("Failed to get helper proxy")
            showError("Cannot connect to helper.\n\nTry restarting the app.")
            return
        }

        log.info("Sending setAWDLEnabled(false) via XPC...")

        proxy.setAWDLEnabled(false, reply: { success in
            DispatchQueue.main.async {
                if success {
                    self.isMonitoring = true
                    AWDLPreferences.shared.isMonitoringEnabled = true
                    AWDLPreferences.shared.lastKnownState = "down"
                    self.onStateChange?()
                    log.info("✅ AWDL monitoring started")
                } else {
                    log.error("❌ Failed to disable AWDL")
                    self.showError("Failed to disable AWDL.\n\nThe helper may not be running correctly.")
                }
            }
        })
    }

    /// Stop monitoring - sends command to helper via XPC
    func stopMonitoring() {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ stopMonitoring() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        guard let proxy = getHelperProxy() else {
            log.warning("No helper proxy - updating state anyway")
            isMonitoring = false
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"
            onStateChange?()
            return
        }

        log.info("Sending setAWDLEnabled(true) via XPC...")

        proxy.setAWDLEnabled(true, reply: { success in
            DispatchQueue.main.async {
                if success {
                    self.isMonitoring = false
                    AWDLPreferences.shared.isMonitoringEnabled = false
                    AWDLPreferences.shared.lastKnownState = "up"
                    self.onStateChange?()
                    log.info("✅ AWDL monitoring stopped - AirDrop/Handoff available")
                } else {
                    log.error("❌ Failed to enable AWDL")
                }
            }
        })
    }

    /// Perform a health check on the helper
    func performHealthCheck() -> (isHealthy: Bool, message: String) {
        log.info("Performing health check...")

        // Check 1: Is helper registered?
        guard isHelperRegistered else {
            log.info("Health check: Helper not registered")
            return (false, "Helper not registered with system")
        }

        // Check 2: Can we connect via XPC?
        if xpcConnection == nil {
            connectXPC()
        }

        guard let proxy = getHelperProxy() else {
            log.info("Health check: Cannot connect to helper")
            return (false, "Cannot connect to helper via XPC")
        }

        // Check 3: Query helper status
        var helperStatus = "Unknown"
        var helperVersion = "Unknown"
        let semaphore = DispatchSemaphore(value: 0)

        proxy.getAWDLStatus(reply: { status in
            helperStatus = status
            semaphore.signal()
        })
        _ = semaphore.wait(timeout: .now() + 2.0)

        proxy.getVersion(reply: { version in
            helperVersion = version
            semaphore.signal()
        })
        _ = semaphore.wait(timeout: .now() + 2.0)

        // Check 4: Check actual AWDL interface status
        let awdlStatus = getAWDLInterfaceStatus()
        log.debug("AWDL interface status: \(awdlStatus)")

        let isAWDLDown = !awdlStatus.contains("UP") || awdlStatus.contains("<DOWN")

        if isMonitoring && !isAWDLDown {
            log.warning("Health check: AWDL is UP despite monitoring being active")
            return (false, "Monitoring active but AWDL is UP - helper may not be functioning")
        }

        let message = "Helper healthy: v\(helperVersion), Status: \(helperStatus)"
        log.info("Health check: \(message)")
        return (true, message)
    }

    /// Test the daemon response time (for Testing Mode feature)
    func testDaemonResponseTime(iterations: Int = 5, completion: @escaping ([(passed: Bool, responseTime: TimeInterval)]) -> Void) {
        log.info("Testing daemon response time (\(iterations) iterations)...")

        var results: [(passed: Bool, responseTime: TimeInterval)] = []

        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                let startTime = Date()

                // Bring AWDL up
                self.runIfconfig(up: true)

                // Small delay for system to process
                Thread.sleep(forTimeInterval: 0.001)

                // Check if AWDL is still down (daemon should have caught it)
                let status = self.getAWDLInterfaceStatus()
                let endTime = Date()

                let responseTime = endTime.timeIntervalSince(startTime)
                let passed = !status.contains("UP") || status.contains("<DOWN")

                results.append((passed: passed, responseTime: responseTime))
                log.debug("Test \(i + 1): passed=\(passed), time=\(String(format: "%.3f", responseTime * 1000))ms")

                // Small delay between tests
                if i < iterations - 1 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }

            DispatchQueue.main.async {
                completion(results)
            }
        }
    }

    // MARK: - Legacy API Support (for compatibility)

    /// Legacy method - redirects to registerHelper
    func installAndStartMonitoring() {
        log.info("installAndStartMonitoring() called - redirecting to registerHelper()")
        registerHelper { success in
            if success {
                self.startMonitoring()

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Setup Complete!"
                    alert.informativeText = "AWDLControl is now running.\n\nAWDL is being kept disabled to prevent network latency spikes.\n\nYou can toggle monitoring from the menu bar."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    /// Legacy check - now checks SMAppService status
    func isDaemonInstalled() -> Bool {
        return isHelperRegistered
    }

    /// Legacy check - now checks XPC connection
    func isDaemonVersionCompatible() -> Bool {
        // In v2.0, version is always compatible since helper is bundled
        return isHelperRegistered
    }

    // MARK: - XPC Connection Management

    /// Connect to helper via XPC
    private func connectXPC() {
        log.debug("Connecting to XPC service: \(self.xpcServiceName)")

        // Invalidate existing connection if any
        xpcConnection?.invalidate()

        let connection = NSXPCConnection(machServiceName: xpcServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: AWDLHelperProtocol.self)

        connection.interruptionHandler = { [weak self] in
            log.warning("XPC connection interrupted")
            DispatchQueue.main.async {
                self?.handleXPCDisconnect()
            }
        }

        connection.invalidationHandler = { [weak self] in
            log.warning("XPC connection invalidated")
            DispatchQueue.main.async {
                self?.handleXPCDisconnect()
            }
        }

        connection.activate()
        xpcConnection = connection

        log.info("XPC connection activated")
    }

    /// Handle XPC disconnect
    private func handleXPCDisconnect() {
        xpcConnection = nil

        // If we were monitoring, try to reconnect
        if isMonitoring {
            log.info("Attempting to reconnect XPC...")
            connectXPC()
        } else {
            isMonitoring = false
            onStateChange?()
        }
    }

    /// Get the helper proxy for making XPC calls
    private func getHelperProxy() -> AWDLHelperProtocol? {
        guard let connection = xpcConnection else {
            log.warning("No XPC connection available")
            return nil
        }

        return connection.remoteObjectProxy as? AWDLHelperProtocol
    }

    // MARK: - Registration Polling

    /// Poll for registration status change
    private func startPollingForRegistration(completion: ((Bool) -> Void)?) {
        log.debug("Starting registration polling...")

        registrationTimer?.invalidate()
        registrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let status = self.helperService.status
            log.debug("Polling: status = \(self.statusDescription(status))")

            switch status {
            case .enabled:
                timer.invalidate()
                self.registrationTimer = nil
                log.info("✅ Helper registration approved")
                self.connectXPC()
                completion?(true)

            case .notRegistered:
                timer.invalidate()
                self.registrationTimer = nil
                log.info("❌ Helper registration denied")
                completion?(false)

            case .requiresApproval, .notFound:
                // Keep polling
                break

            @unknown default:
                break
            }
        }
    }

    // MARK: - Helper Methods

    /// Get human-readable status description
    private func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "Not Registered"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Requires Approval"
        case .notFound: return "Not Found"
        @unknown default: return "Unknown"
        }
    }

    /// Get current AWDL interface status via ifconfig
    private func getAWDLInterfaceStatus() -> String {
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

    /// Run ifconfig to bring AWDL up or down (for testing only)
    private func runIfconfig(up: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["awdl0", up ? "up" : "down"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            log.error("Error running ifconfig: \(error.localizedDescription)")
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
