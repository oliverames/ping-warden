//
//  AWDLMonitor.swift
//  AWDLControl
//
//  Controls the AWDL helper daemon via SMAppService and XPC.
//
//  Copyright (c) 2025 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

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

    /// Maximum time to wait for registration approval (60 seconds)
    private let registrationTimeoutSeconds: TimeInterval = 60.0

    /// Maximum XPC connection retry attempts
    private let maxXPCRetries = 3

    /// Current XPC retry count
    private var xpcRetryCount = 0

    /// SMAppService instance for the helper daemon
    private lazy var helperService: SMAppService = {
        return SMAppService.daemon(plistName: helperPlistName)
    }()

    /// XPC connection to the helper (use thread-safe accessor)
    private var _xpcConnection: NSXPCConnection?

    /// Lock for thread-safe access to state
    private let stateLock = NSLock()
    private var _isMonitoring = false

    /// Flag to prevent recursive registration
    private var _isRegisteringHelper = false

    /// Counter to prevent infinite registration retries
    private var _registrationAttempts = 0
    private let maxRegistrationAttempts = 3

    /// Flag to prevent re-entrant XPC invalidation handling
    private var _isHandlingInvalidation = false

    /// Thread-safe access to XPC connection
    private var xpcConnection: NSXPCConnection? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _xpcConnection
        }
        set {
            stateLock.lock()
            _xpcConnection = newValue
            stateLock.unlock()
        }
    }

    /// Thread-safe access to registration flag
    private var isRegisteringHelper: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isRegisteringHelper
        }
        set {
            stateLock.lock()
            _isRegisteringHelper = newValue
            stateLock.unlock()
        }
    }

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

    /// Timer for registration timeout
    private var registrationTimeoutTimer: Timer?

    private init() {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("AWDLMonitor v2.0.1 initializing (SMAppService + XPC)...")
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

    /// Check if monitoring is currently active (thread-safe)
    var isMonitoringActive: Bool {
        stateLock.lock()
        let active = _isMonitoring && _xpcConnection != nil
        stateLock.unlock()
        return active
    }

    /// Validate that the helper binary and plist exist in the app bundle
    private func validateHelperBundle() -> (valid: Bool, error: String?) {
        let appBundle = Bundle.main.bundlePath

        let helperBinaryPath = "\(appBundle)/Contents/MacOS/AWDLControlHelper"
        let helperPlistPath = "\(appBundle)/Contents/Library/LaunchDaemons/\(helperPlistName)"

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: helperBinaryPath) {
            log.error("Helper binary not found at: \(helperBinaryPath)")
            return (false, "Helper binary not found in app bundle.\n\nPlease reinstall the app.")
        }

        if !fileManager.fileExists(atPath: helperPlistPath) {
            log.error("Helper plist not found at: \(helperPlistPath)")
            return (false, "Helper configuration not found in app bundle.\n\nPlease reinstall the app.")
        }

        // Verify binary is executable
        if !fileManager.isExecutableFile(atPath: helperBinaryPath) {
            log.error("Helper binary is not executable: \(helperBinaryPath)")
            return (false, "Helper binary is not executable.\n\nPlease reinstall the app.")
        }

        log.debug("Helper bundle validation passed")
        return (true, nil)
    }

    /// Register helper with SMAppService
    /// This triggers a one-time system approval prompt (not a password dialog)
    func registerHelper(completion: ((Bool) -> Void)? = nil) {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ registerHelper() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Validate helper bundle before attempting registration
        let validation = validateHelperBundle()
        if !validation.valid {
            log.error("Helper bundle validation failed: \(validation.error ?? "unknown")")
            DispatchQueue.main.async { [weak self] in
                self?.showError(validation.error ?? "Helper bundle validation failed")
            }
            completion?(false)
            return
        }

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
            // Prevent recursive registration
            guard !isRegisteringHelper else {
                log.debug("Already registering helper, skipping")
                return
            }

            // Prevent infinite retry loops
            stateLock.lock()
            _registrationAttempts += 1
            let attempts = _registrationAttempts
            stateLock.unlock()

            if attempts > maxRegistrationAttempts {
                log.error("Max registration attempts (\(maxRegistrationAttempts)) exceeded, giving up")
                showError("Helper registration failed after multiple attempts.\n\nPlease try restarting the app or check System Settings → Login Items.")
                return
            }

            isRegisteringHelper = true
            registerHelper { success in
                self.isRegisteringHelper = false
                if success && self.isHelperRegistered {
                    // Reset attempts on success
                    self.stateLock.lock()
                    self._registrationAttempts = 0
                    self.stateLock.unlock()
                    self.startMonitoring()
                }
            }
            return
        }

        // Ensure XPC connection with retry
        if xpcConnection == nil {
            connectXPCWithRetry()
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
            stateLock.lock()
            _isMonitoring = false
            stateLock.unlock()
            AWDLPreferences.shared.isMonitoringEnabled = false
            AWDLPreferences.shared.lastKnownState = "up"
            onStateChange?()
            return
        }

        log.info("Sending setAWDLEnabled(true) via XPC...")

        proxy.setAWDLEnabled(true, reply: { success in
            DispatchQueue.main.async {
                if success {
                    self.stateLock.lock()
                    self._isMonitoring = false
                    self.stateLock.unlock()
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

        // Check 3: Query helper status with proper timeout handling
        var helperStatus = "Unknown"
        var helperVersion = "Unknown"
        var statusTimedOut = false
        var versionTimedOut = false
        let statusSemaphore = DispatchSemaphore(value: 0)
        let versionSemaphore = DispatchSemaphore(value: 0)

        proxy.getAWDLStatus(reply: { status in
            helperStatus = status
            statusSemaphore.signal()
        })
        if statusSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
            log.warning("Health check: getAWDLStatus timed out")
            statusTimedOut = true
        }

        proxy.getVersion(reply: { version in
            helperVersion = version
            versionSemaphore.signal()
        })
        if versionSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
            log.warning("Health check: getVersion timed out")
            versionTimedOut = true
        }

        // If both timed out, helper is not responding
        if statusTimedOut && versionTimedOut {
            return (false, "Helper not responding to XPC calls (timed out)")
        }

        // Check 4: Check actual AWDL interface status
        let awdlStatus = getAWDLInterfaceStatus()
        log.debug("AWDL interface status: \(awdlStatus)")

        // Parse AWDL status - check for DOWN flag or absence of UP in flags section
        let isAWDLDown = awdlStatus.contains("<DOWN") ||
                         (awdlStatus.contains("flags=") && !awdlStatus.contains("<UP"))

        if isMonitoring && !isAWDLDown {
            log.warning("Health check: AWDL is UP despite monitoring being active")
            return (false, "Monitoring active but AWDL is UP - helper may not be functioning")
        }

        let message = "Helper healthy: v\(helperVersion), Status: \(helperStatus)"
        log.info("Health check: \(message)")
        return (true, message)
    }

    /// Test the helper response time (for Testing Mode feature)
    /// Note: This test only works when monitoring is active, as it relies on
    /// the helper bringing AWDL back down after we bring it up.
    func testHelperResponseTime(iterations: Int = 5, completion: @escaping ([(passed: Bool, responseTime: TimeInterval)]) -> Void) {
        log.info("Testing helper response time (\(iterations) iterations)...")

        // Warn if monitoring is not active - test results won't be meaningful
        guard isMonitoringActive else {
            log.warning("testHelperResponseTime called but monitoring is not active - test will fail")
            DispatchQueue.main.async {
                // Return all failures since monitoring isn't active
                let results = (0..<iterations).map { _ in (passed: false, responseTime: 0.0) }
                completion(results)
            }
            return
        }

        var results: [(passed: Bool, responseTime: TimeInterval)] = []

        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                let startTime = Date()

                // Bring AWDL up
                self.runIfconfig(up: true)

                // Small delay for system to process
                Thread.sleep(forTimeInterval: 0.001)

                // Check if AWDL is still down (helper should have caught it)
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

    /// Connect to helper via XPC with retry logic
    private func connectXPCWithRetry() {
        xpcRetryCount = 0
        connectXPC()
    }

    /// Connect to helper via XPC
    private func connectXPC() {
        log.debug("Connecting to XPC service: \(self.xpcServiceName)")

        // Invalidate existing connection if any
        stateLock.lock()
        _xpcConnection?.invalidate()
        stateLock.unlock()

        // Use .privileged for daemon registered via SMAppService
        // This is required because the daemon runs as root
        let connection = NSXPCConnection(machServiceName: xpcServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AWDLHelperProtocol.self)

        connection.interruptionHandler = { [weak self] in
            log.warning("XPC connection interrupted")
            DispatchQueue.main.async {
                self?.handleXPCInterruption()
            }
        }

        connection.invalidationHandler = { [weak self] in
            log.warning("XPC connection invalidated")
            DispatchQueue.main.async {
                self?.handleXPCInvalidation()
            }
        }

        connection.activate()

        stateLock.lock()
        _xpcConnection = connection
        stateLock.unlock()

        // Reset retry count on successful activation
        xpcRetryCount = 0

        log.info("XPC connection activated")

        // Validate connection by attempting a simple query with timeout
        validateXPCConnection()
    }

    /// Validate XPC connection is actually working
    private func validateXPCConnection() {
        guard let proxy = getHelperProxy() else {
            log.warning("XPC validation: No proxy available")
            return
        }

        let validationSemaphore = DispatchSemaphore(value: 0)
        var isValid = false

        proxy.getVersion(reply: { version in
            isValid = !version.isEmpty
            validationSemaphore.signal()
        })

        // Wait up to 2 seconds for validation
        if validationSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
            log.warning("XPC validation: Connection timeout - helper may not be running")
        } else if isValid {
            log.debug("XPC validation: Connection verified successfully")
        } else {
            log.warning("XPC validation: Invalid response from helper")
        }
    }

    /// Handle XPC interruption (temporary disconnect)
    private func handleXPCInterruption() {
        // Interruption is recoverable - the connection can be resumed
        log.info("XPC interruption - connection may recover automatically")
    }

    /// Handle XPC invalidation (permanent disconnect)
    private func handleXPCInvalidation() {
        // Prevent re-entrant handling
        stateLock.lock()
        if _isHandlingInvalidation {
            stateLock.unlock()
            log.debug("Already handling XPC invalidation, skipping")
            return
        }
        _isHandlingInvalidation = true
        _xpcConnection = nil
        let wasMonitoring = _isMonitoring
        stateLock.unlock()

        defer {
            stateLock.lock()
            _isHandlingInvalidation = false
            stateLock.unlock()
        }

        // If we were monitoring, try to reconnect with exponential backoff
        if wasMonitoring {
            xpcRetryCount += 1
            if xpcRetryCount <= maxXPCRetries {
                let delay = pow(2.0, Double(xpcRetryCount - 1)) // 1s, 2s, 4s
                log.info("Attempting XPC reconnect in \(delay)s (attempt \(xpcRetryCount)/\(maxXPCRetries))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.connectXPC()
                }
            } else {
                log.error("Max XPC retry attempts exceeded")
                stateLock.lock()
                _isMonitoring = false
                stateLock.unlock()
                onStateChange?()
                showError("Lost connection to helper.\n\nPlease restart the app.")
            }
        } else {
            onStateChange?()
        }
    }

    /// Get the helper proxy for making XPC calls (thread-safe)
    /// Uses remoteObjectProxyWithErrorHandler to properly handle XPC errors
    private func getHelperProxy() -> AWDLHelperProtocol? {
        // Get connection under lock to avoid TOCTOU race
        stateLock.lock()
        let currentConnection = _xpcConnection
        stateLock.unlock()

        guard let xpc = currentConnection else {
            log.warning("No XPC connection available")
            return nil
        }

        return xpc.remoteObjectProxyWithErrorHandler { error in
            log.error("XPC proxy error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.handleXPCInvalidation()
            }
        } as? AWDLHelperProtocol
    }

    // MARK: - Registration Polling

    /// Poll for registration status change with timeout
    private func startPollingForRegistration(completion: ((Bool) -> Void)?) {
        log.debug("Starting registration polling (timeout: \(registrationTimeoutSeconds)s)...")

        // Cancel any existing timers
        registrationTimer?.invalidate()
        registrationTimeoutTimer?.invalidate()

        // Set up timeout timer
        registrationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: registrationTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            log.warning("Registration polling timed out after \(self.registrationTimeoutSeconds)s")
            self.registrationTimer?.invalidate()
            self.registrationTimer = nil
            self.registrationTimeoutTimer = nil

            DispatchQueue.main.async {
                self.showError("Registration timed out.\n\nPlease approve the helper in System Settings → Login Items and try again.")
            }
            completion?(false)
        }

        // Set up polling timer
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
                self.registrationTimeoutTimer?.invalidate()
                self.registrationTimeoutTimer = nil
                log.info("✅ Helper registration approved")
                self.connectXPC()
                completion?(true)

            case .notRegistered:
                timer.invalidate()
                self.registrationTimer = nil
                self.registrationTimeoutTimer?.invalidate()
                self.registrationTimeoutTimer = nil
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
