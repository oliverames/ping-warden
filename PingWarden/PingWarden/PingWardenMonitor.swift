//
//  PingWardenMonitor.swift
//  PingWarden
//
//  Controls the AWDL helper daemon via SMAppService and XPC.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import AppKit
import ServiceManagement
import os.log

/// Unified logger for PingWardenMonitor - logs to both Console.app and file
private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "Monitor")

/// Signpost for performance measurement
private let signposter = OSSignposter(subsystem: "com.amesvt.pingwarden", category: "Performance")

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Controls the AWDL helper daemon via SMAppService and XPC
/// In v2.x, the helper runs as a bundled LaunchDaemon registered via SMAppService
/// No more password prompts - just one-time system approval
///
/// Architecture (v2.x):
/// - Helper binary bundled in Contents/MacOS/PingWardenHelper
/// - Plist bundled in Contents/Library/LaunchDaemons/com.amesvt.pingwarden.helper.plist
/// - Communication via XPC (com.amesvt.pingwarden.xpc)
/// - Helper exits when app quits (via XPC connection invalidation)
class PingWardenMonitor: @unchecked Sendable {
    static let shared = PingWardenMonitor()

    /// XPC service name - must match MachServices key in plist
    private let xpcServiceName = "com.amesvt.pingwarden.xpc"

    /// Plist filename for SMAppService - must match file in Contents/Library/LaunchDaemons/
    private let helperPlistName = "com.amesvt.pingwarden.helper.plist"

    /// Maximum time to wait for registration approval (60 seconds)
    private let registrationTimeoutSeconds: TimeInterval = 60.0

    /// Maximum XPC connection retry attempts
    private let maxXPCRetries = 3

    /// How long the helper gets to answer a validation request.
    private var helperReplyTimeout: TimeInterval = 2.0

    /// Pause between attempts while confirming the helper answers.
    private var helperRetryDelay: TimeInterval = 1.0

    /// Current XPC retry count (protected by stateLock)
    private var _xpcRetryCount = 0

    /// SMAppService instance for the helper daemon
    private lazy var helperService: SMAppService = {
        return SMAppService.daemon(plistName: helperPlistName)
    }()

    /// XPC connection to the helper (use thread-safe accessor)
    private var _xpcConnection: NSXPCConnection?

    /// Lock for thread-safe access to state
    private let stateLock = NSLock()
    private var _isMonitoring = false
    private var _confirmedMonitoring = false

    /// Flag to prevent recursive registration
    private var _isRegisteringHelper = false

    /// Counter to prevent infinite registration retries
    private var _registrationAttempts = 0
    private let maxRegistrationAttempts = 3

    /// Flag to prevent re-entrant XPC invalidation handling
    private var _isHandlingInvalidation = false

    /// Monotonic command token. A newer protection request invalidates older
    /// replies so delayed XPC callbacks cannot overwrite the user's latest
    /// choice after a rapid on/off transition or reconnect.
    private var _protectionOperationGeneration: UInt64 = 0
    private var _desiredProtectionEnabled = false

    /// Why the most recent protection command failed, or `nil` after a
    /// success. Callers use it to tell a silent helper from one that
    /// answered with a failure.
    private var _lastCommandFailure: HelperCommandFailure?

    /// Why the most recent connection validation failed, kept so the helper
    /// test can say "rejected" rather than "timed out".
    private var _lastConnectionFailure: HelperCommandFailure?

    /// True while a repair rebuilds the helper's registration. The repair
    /// tears the helper down on purpose, so reconnect exhaustion waits for
    /// it instead of reporting a lost connection.
    private var _isRepairingHelper = false
    private var _reconnectDeferredForRepair = false

    /// Everyone waiting on the repair in flight (main-thread confined).
    /// Overlapping repairs join it instead of unregistering each other.
    private var repairCompletions: [@Sendable (Bool) -> Void] = []

    /// The enable command awaiting the helper (main-thread confined). A
    /// second enable while one is in flight joins it, so launch sends one
    /// command instead of three and no reply supersedes its twin.
    private var pendingEnable: EnableRequest?

    /// Stop commands awaiting the helper (main-thread confined).
    private var pendingStopCount = 0

    /// Callers of one enable command. Main-thread confined; the unchecked
    /// conformance lets the XPC reply closure carry it back to main.
    private final class EnableRequest: @unchecked Sendable {
        let operationID: UInt64
        var persistUserPreference: Bool
        private var waiters: [@Sendable (Bool) -> Void] = []

        init(operationID: UInt64, persistUserPreference: Bool, completion: (@Sendable (Bool) -> Void)?) {
            self.operationID = operationID
            self.persistUserPreference = persistUserPreference
            if let completion { waiters.append(completion) }
        }

        func join(persistUserPreference: Bool, completion: (@Sendable (Bool) -> Void)?) {
            self.persistUserPreference = self.persistUserPreference || persistUserPreference
            if let completion { waiters.append(completion) }
        }

        func finish(_ success: Bool) {
            let current = waiters
            waiters = []
            current.forEach { $0(success) }
        }
    }

    /// Receives, on the main queue, errors from paths nobody directly
    /// asked for: reconnect exhaustion and a failed reassert. They must not
    /// raise an alert over a game, so the coordinator publishes them where
    /// the menu, Dashboard, and Settings already show errors.
    var automatedErrorHandler: (@Sendable (String) -> Void)?

    /// Called on the main queue whenever the helper answers anything.
    var helperResponseHandler: (@Sendable () -> Void)?

    /// The most recent setup or repair failure, kept so a caller with its
    /// own error surface can show it instead of a second alert. Main-thread
    /// confined.
    private(set) var lastSetupFailureMessage: String?

    /// Whether an alert should accompany the registration poll's timeout.
    /// Main-thread confined, like the poll itself.
    private var pendingRegistrationPresentsErrors = true

    /// Thread-safe access to XPC connection
    private var xpcConnection: NSXPCConnection? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _xpcConnection
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _xpcConnection = newValue
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
            defer { stateLock.unlock() }
            _isRegisteringHelper = newValue
        }
    }

    /// Thread-safe access to XPC retry count
    private var xpcRetryCount: Int {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _xpcRetryCount
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _xpcRetryCount = newValue
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
            defer { stateLock.unlock() }
            _isMonitoring = newValue
            _confirmedMonitoring = newValue
        }
    }

    /// Thread-safe registry of state-change observer callbacks.
    private let stateObservers = StateObserverRegistry()

    /// Timer for polling registration status (main-thread confined)
    private var registrationTimer: Timer?

    /// Timer for registration timeout (main-thread confined)
    private var registrationTimeoutTimer: Timer?

    /// Last helper registration status read from SMAppService, and when
    /// (system uptime). Protected by stateLock. Reading the status is a
    /// synchronous call into the system, and the Dashboard and menu read it
    /// several times per redraw, so UI reads share this value. Decisions
    /// that register, repair, or command the helper still read it live.
    private var _cachedHelperStatus: SMAppService.Status?
    private var _cachedHelperStatusTime: TimeInterval = 0

    /// Longest a cached status is trusted. Registration changes made in
    /// System Settings send the app no notification, and returning to the
    /// app does not always activate it (a menu bar click, for example), so
    /// the cache also expires on its own.
    private let helperStatusCacheLifetime: TimeInterval = 2

    /// Completion of the in-flight registration poll (main-thread confined).
    /// Held so a superseding poll can still deliver `false` to the previous
    /// caller — dropping it silently would wedge `isRegisteringHelper`.
    private var pendingRegistrationCompletion: (@Sendable (Bool) -> Void)?

    private init() {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        log.info("PingWardenMonitor v\(version) initializing (SMAppService + XPC)...")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let status = refreshHelperStatus()
        log.info("  Helper service status: \(self.statusDescription(status))")
        log.info("  XPC service name: \(self.xpcServiceName)")
        log.info("  Helper plist: \(self.helperPlistName)")

        // Approving or removing the helper in System Settings happens while
        // Ping Warden is in the background; coming back re-reads it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateHelperStatus()
        }

        // If helper is already registered, connect to it
        if status == .enabled {
            log.info("  Helper already enabled, connecting XPC...")
            connectXPC()

            // Check if we should restore monitoring state. The persisted
            // intent alone is not enough: the license gate must still
            // hold, or an expired transition (or a hand-written
            // preference) would put AWDL down at every launch.
            if PingWardenPreferences.shared.isMonitoringEnabled {
                if !LicenseManager.launchGateAllowsProtection {
                    log.info("  Monitoring restore blocked: no valid license entitlement at launch")
                } else if let pausedUntil = PingWardenPreferences.shared.protectionPauseUntil,
                   pausedUntil > Date() {
                    // A persisted pause outranks the stored protection intent
                    // until it expires; the coordinator's pause timer resumes
                    // blocking when it fires.
                    log.info("  Monitoring restore deferred: paused until \(pausedUntil)")
                } else {
                    log.info("  Restoring monitoring state from preferences")
                    startMonitoring(persistUserPreference: false)
                }
            }
        }

        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Public API

    /// Check if helper is registered with SMAppService. Served from a
    /// short-lived cache; see `_cachedHelperStatus`.
    var isHelperRegistered: Bool {
        registrationStatus == .enabled
    }

    /// Current registration status, served from a short-lived cache.
    var registrationStatus: SMAppService.Status {
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let cached = _cachedHelperStatus
        let age = now - _cachedHelperStatusTime
        stateLock.unlock()
        if let cached, age < helperStatusCacheLifetime {
            return cached
        }
        return refreshHelperStatus()
    }

    /// Read the registration status from the system and cache it. Call
    /// after anything that may have changed the registration.
    @discardableResult
    func refreshHelperStatus() -> SMAppService.Status {
        // Never hold stateLock across the system call.
        let status = helperService.status
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        _cachedHelperStatus = status
        _cachedHelperStatusTime = now
        stateLock.unlock()
        return status
    }

    /// Whether the helper is registered right now, from a live read. Used
    /// by decisions that register, repair, or command the helper, which
    /// must not act on a stale value.
    private var helperIsEnabledNow: Bool {
        refreshHelperStatus() == .enabled
    }

    private func invalidateHelperStatus() {
        stateLock.lock()
        _cachedHelperStatus = nil
        stateLock.unlock()
    }

    /// Check if monitoring is currently active (thread-safe)
    var isMonitoringActive: Bool {
        stateLock.lock()
        let active = _isMonitoring && _confirmedMonitoring && _xpcConnection != nil
        stateLock.unlock()
        return active
    }

    /// Whether Ping Warden has requested protection, even if XPC is briefly
    /// reconnecting. UI that distinguishes "reconnecting" from "off" should
    /// use this alongside `isMonitoringActive`.
    var isMonitoringRequested: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isMonitoring
    }

    /// Whether the latest protection request asks for protection, including
    /// a first enable whose reply has not arrived. Quit and Off must still
    /// send a stop in that window, or the late enable leaves AWDL down.
    var isProtectionDesired: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _desiredProtectionEnabled
    }

    /// Whether a protection command is waiting on the helper. Main thread.
    var isProtectionCommandInFlight: Bool {
        pendingEnable != nil || pendingStopCount > 0
    }

    /// Whether a repair is rebuilding the helper's registration.
    var isRepairingHelper: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRepairingHelper
    }

    /// Why the most recent protection command failed; `nil` after success.
    var lastCommandFailure: HelperCommandFailure? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastCommandFailure
    }

    private func recordCommandFailure(_ failure: HelperCommandFailure?) {
        stateLock.lock()
        _lastCommandFailure = failure
        stateLock.unlock()
    }

    /// A rejection seen by the proxy outranks the timeout it causes.
    private func recordCommandTimeout() {
        stateLock.lock()
        if _lastCommandFailure == nil {
            _lastCommandFailure = .timedOut
        }
        stateLock.unlock()
    }

    private func helperResponded() {
        let handler = helperResponseHandler
        DispatchQueue.main.async { handler?() }
    }

    private func reportAutomatedError(_ message: String) {
        log.error("Reporting without an alert: \(message, privacy: .public)")
        let handler = automatedErrorHandler
        DispatchQueue.main.async { handler?(message) }
    }

    /// Adopt state that a signed extension already applied directly through
    /// the helper's authenticated XPC listener. The distributed notification
    /// that triggers this path is only a display invalidation signal and never
    /// causes a privileged command.
    ///
    /// The adopted value comes from shared defaults, which any process
    /// running as this user can write, and the notification itself is
    /// unauthenticated. Neither can move the radio, but a stale or
    /// hand-written value could leave the menu saying "Protected" over an
    /// interface that is up. So the adoption is provisional: the helper,
    /// which alone knows what it is enforcing, is asked to confirm and its
    /// answer wins when it disagrees.
    func adoptExternallyAppliedMonitoringState(_ active: Bool) {
        stateLock.lock()
        _protectionOperationGeneration &+= 1
        let operationID = _protectionOperationGeneration
        // Rechecking an already-confirmed state must not interrupt a session.
        // A new positive hint remains unconfirmed and cannot authorize a
        // command before the helper's state query completes.
        let remainsConfirmed = active && _isMonitoring && _confirmedMonitoring && _xpcConnection != nil
        _isMonitoring = active
        _confirmedMonitoring = remainsConfirmed
        _desiredProtectionEnabled = remainsConfirmed && _desiredProtectionEnabled
        stateLock.unlock()
        notifyStateChange()
        confirmAdoptedStateWithHelper(expectedActive: active, operationID: operationID)
    }

    /// Reconcile a provisionally adopted state against the helper. A
    /// missing connection or a dropped reply leaves the adopted state
    /// unconfirmed and cannot authorize a protection command.
    private func confirmAdoptedStateWithHelper(expectedActive: Bool, operationID: UInt64) {
        guard helperIsEnabledNow else { return }
        if xpcConnection == nil {
            connectXPC()
        }
        guard let proxy = getHelperProxy() else { return }

        proxy.isAWDLEnabled(reply: { [weak self] awdlEnabled in
            guard let monitor = self else { return }
            DispatchQueue.main.async {
                monitor.helperResponded()
                // The helper allows AWDL up when protection is off.
                let helperSaysActive = !awdlEnabled
                guard monitor.isCurrentProtectionOperation(operationID) else { return }
                if helperSaysActive != expectedActive {
                    log.warning("Externally reported protection state (\(expectedActive)) disagrees with the helper (\(helperSaysActive)); adopting the helper's state")
                }
                monitor.stateLock.lock()
                monitor._isMonitoring = helperSaysActive
                monitor._confirmedMonitoring = helperSaysActive
                monitor._desiredProtectionEnabled = helperSaysActive
                monitor.stateLock.unlock()
                PingWardenPreferences.shared.effectiveMonitoringEnabled = helperSaysActive
                PingWardenPreferences.shared.lastKnownState = helperSaysActive ? "down" : "up"
                monitor.notifyStateChange()
            }
        })
    }

    /// Register for monitor state changes. Returns a token that can be removed later.
    @discardableResult
    func addStateObserver(_ observer: @escaping @Sendable () -> Void) -> UUID {
        stateObservers.add(observer)
    }

    /// Remove a previously registered state observer.
    func removeStateObserver(_ token: UUID) {
        stateObservers.remove(token)
    }

    /// Validate that the helper binary and plist exist in the app bundle.
    /// Returns `nil` on success or a `ValidationFailure` describing the first
    /// missing/invalid piece. Logging is handled here so the underlying
    /// validator stays pure-Foundation and testable.
    private func validateHelperBundle() -> HelperBundleValidator.ValidationFailure? {
        let failure = HelperBundleValidator.validate(
            appBundlePath: Bundle.main.bundlePath,
            helperPlistName: helperPlistName
        )
        if let failure {
            log.error("Helper bundle validation failed at: \(failure.path, privacy: .public)")
        } else {
            log.debug("Helper bundle validation passed")
        }
        return failure
    }

    /// Register helper with SMAppService
    /// This triggers a one-time system approval prompt (not a password dialog)
    /// Pass `presentsErrors: false` when the caller shows the failure itself,
    /// through `lastSetupFailureMessage`, so it never stacks a second alert.
    func registerHelper(
        presentsErrors: Bool = true,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ registerHelper() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Validate helper bundle before attempting registration
        if let failure = validateHelperBundle() {
            reportSetupFailureOnMain(
                failure.userMessage,
                title: failure.userTitle,
                presentsErrors: presentsErrors
            )
            completion?(false)
            return
        }

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("RegisterHelper", id: signpostID)

        let currentStatus = refreshHelperStatus()
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
            startPollingForRegistration(presentsErrors: presentsErrors, completion: completion)
            signposter.endInterval("RegisterHelper", state)
            return

        case .notRegistered, .notFound:
            log.info("Registering helper with SMAppService...")
            do {
                try helperService.register()
                refreshHelperStatus()
                log.info("Registration request submitted")
                // Start polling for approval
                startPollingForRegistration(presentsErrors: presentsErrors, completion: completion)
                signposter.endInterval("RegisterHelper", state)
            } catch let error as NSError {
                log.error("Registration failed: \(error.localizedDescription) (code: \(error.code))")
                signposter.endInterval("RegisterHelper", state)

                // Check if this is "Operation not permitted" - means user needs to approve first
                // Error domain is NSPOSIXErrorDomain with code 1 (EPERM), or
                // SMAppService may throw with domain NSCocoaErrorDomain
                let isPermissionError = error.localizedDescription.contains("Operation not permitted") ||
                                        error.localizedDescription.contains("not permitted") ||
                                        error.domain == "SMAppServiceErrorDomain" ||
                                        error.domain.contains("ServiceManagement") ||
                                        (error.domain == NSPOSIXErrorDomain && error.code == 1)

                if isPermissionError {
                    log.info("Registration requires user approval first - opening System Settings")
                    // Open System Settings to Login Items so user can approve
                    SMAppService.openSystemSettingsLoginItems()
                    // Start polling for the user to approve
                    startPollingForRegistration(presentsErrors: presentsErrors, completion: completion)
                } else {
                    reportSetupFailureOnMain(
                        "Ping Warden could not register its helper. \(error.localizedDescription)",
                        title: "Helper Setup Failed",
                        presentsErrors: presentsErrors
                    )
                    completion?(false)
                }
            }

        @unknown default:
            log.error("Unknown helper status: \(String(describing: currentStatus))")
            signposter.endInterval("RegisterHelper", state)
            completion?(false)
        }
    }

    /// Ask the helper for its version, retrying a few times so a daemon that
    /// launchd is still spawning gets a chance. `activate()` succeeding
    /// locally proves nothing, and an enabled registration can outlive the
    /// launchd job behind it, so only a reply counts. The probe reuses the
    /// current connection: replacing it would drop a protection command
    /// already in flight on it. Completes on the main queue.
    func confirmHelperResponds(
        attempts: Int = 3,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.confirmHelperResponds(attempts: attempts, completion: completion)
            }
            return
        }
        guard helperIsEnabledNow else {
            completion(false)
            return
        }
        let retryIfSilent: @Sendable (Bool) -> Void = { [weak self] responded in
            let monitor = self
            DispatchQueue.main.async {
                guard let monitor, !responded, attempts > 1 else {
                    completion(responded)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + monitor.helperRetryDelay) {
                    monitor.confirmHelperResponds(attempts: attempts - 1, completion: completion)
                }
            }
        }
        if xpcConnection == nil {
            connectXPC(onValidated: retryIfSilent)
        } else {
            validateXPCConnection(completion: retryIfSilent)
        }
    }

    /// Repair a helper that should be working. A registration that answers
    /// is left alone. A registration that is enabled but silent is rebuilt:
    /// unregister, then register again, which recreates the launchd job that
    /// Background Task Management still claims exists. Macs that approved the
    /// helper before re-register without another prompt. Success is reported
    /// only after the helper actually answers. Runs only from an explicit
    /// user action, never automatically. Completes on the main queue.
    ///
    /// Only one repair runs at a time. A second request joins the first and
    /// receives its result; starting another would unregister the helper the
    /// first one just rebuilt.
    func repairHelperRegistration(
        presentsErrors: Bool = true,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.repairHelperRegistration(presentsErrors: presentsErrors, completion: completion)
            }
            return
        }
        repairCompletions.append(completion)
        guard repairCompletions.count == 1 else {
            log.info("Joining the helper repair already in progress")
            return
        }
        stateLock.lock()
        _isRepairingHelper = true
        _isRegisteringHelper = true
        stateLock.unlock()
        lastSetupFailureMessage = nil
        notifyStateChange()

        let finish: @Sendable (Bool) -> Void = { [weak self] repaired in
            let monitor = self
            DispatchQueue.main.async {
                monitor?.finishRepair(repaired)
            }
        }
        let registerThenConfirm: @Sendable () -> Void = { [weak self] in
            guard let self else {
                finish(false)
                return
            }
            self.registerHelper(presentsErrors: presentsErrors) { registered in
                DispatchQueue.main.async {
                    guard registered else {
                        finish(false)
                        return
                    }
                    self.confirmHelperResponds(completion: finish)
                }
            }
        }

        guard helperIsEnabledNow else {
            registerThenConfirm()
            return
        }

        confirmHelperResponds { [weak self] responds in
            guard let self else {
                finish(false)
                return
            }
            if responds {
                finish(true)
                return
            }
            // Never tear down a registration that cannot be rebuilt.
            if let failure = self.validateHelperBundle() {
                self.reportSetupFailure(
                    failure.userMessage,
                    title: failure.userTitle,
                    presentsErrors: presentsErrors
                )
                finish(false)
                return
            }
            log.warning("Helper is registered but not answering; rebuilding its registration")
            let plistName = self.helperPlistName
            Task { @MainActor in
                do {
                    try await SMAppService.daemon(plistName: plistName).unregister()
                    self.refreshHelperStatus()
                    log.info("Stale helper registration removed")
                } catch {
                    // Continue: registering over a stale record can still
                    // recreate the job, and the final reply check decides.
                    log.error("Helper unregister during repair failed: \(error.localizedDescription)")
                }
                registerThenConfirm()
            }
        }
    }

    /// Deliver the repair's result to every caller and settle any reconnect
    /// the repair held back. Main-thread only.
    private func finishRepair(_ repaired: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        let completions = repairCompletions
        repairCompletions = []
        stateLock.lock()
        _isRepairingHelper = false
        _isRegisteringHelper = false
        let reconnectWasDeferred = _reconnectDeferredForRepair
        _reconnectDeferredForRepair = false
        if repaired {
            // The drops the repair caused were deliberate, not failures.
            _xpcRetryCount = 0
        }
        let stillRequested = _isMonitoring
        let hasConnection = _xpcConnection != nil
        stateLock.unlock()

        if reconnectWasDeferred, stillRequested, !hasConnection {
            if repaired {
                // Validation reasserts the current request once it answers.
                connectXPC()
            } else {
                // The repair reports its own failure, so giving up here
                // adds no second message.
                log.error("Helper repair failed while protection was requested; giving up the reconnect")
                stateLock.lock()
                _isMonitoring = false
                _confirmedMonitoring = false
                _desiredProtectionEnabled = false
                stateLock.unlock()
                PingWardenPreferences.shared.effectiveMonitoringEnabled = false
            }
        }
        notifyStateChange()
        completions.forEach { $0(repaired) }
    }

    /// Whether awdl0 reads up right now, from its interface flags and without
    /// the helper. `nil` when the flags cannot be read.
    func awdlInterfaceIsUp() async -> Bool? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: HelperRecovery.interfaceIsUp(flagsLine: self.getAWDLInterfaceStatus()))
            }
        }
    }

    /// Start monitoring - sends command to helper via XPC
    func startMonitoring(
        persistUserPreference: Bool = true,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startMonitoring(persistUserPreference: persistUserPreference, completion: completion)
            }
            return
        }
        // Join an enable that is still current rather than superseding it.
        // Launch reaches this from the init restore and the launch reconcile;
        // separate commands would stale each other's replies and leave the
        // earlier caller reporting failure while protection turns on.
        if let pendingEnable, isCurrentProtectionOperation(pendingEnable.operationID) {
            log.info("Joining the enable-protection command already in flight")
            pendingEnable.join(persistUserPreference: persistUserPreference, completion: completion)
            return
        }
        let operationID = beginProtectionOperation(enabled: true)
        startMonitoring(
            operationID: operationID,
            persistUserPreference: persistUserPreference,
            completion: completion
        )
    }

    private func startMonitoring(
        operationID: UInt64,
        persistUserPreference: Bool,
        completion: (@Sendable (Bool) -> Void)?
    ) {
        guard isCurrentProtectionOperation(operationID), LicenseManager.launchGateAllowsProtection else {
            abandonEnable(operationID)
            completion?(false)
            return
        }
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ startMonitoring() called                            │")
        log.info("└─────────────────────────────────────────────────────┘")

        // Check if helper is registered
        guard helperIsEnabledNow else {
            log.info("Helper not registered - starting registration flow")
            // Prevent recursive registration
            guard !isRegisteringHelper, !isRepairingHelper else {
                log.debug("Already registering helper, skipping")
                abandonEnable(operationID)
                completion?(false)
                return
            }

            // Prevent infinite retry loops
            stateLock.lock()
            _registrationAttempts += 1
            let attempts = _registrationAttempts
            stateLock.unlock()

            if attempts > maxRegistrationAttempts {
                log.error("Max registration attempts (\(self.maxRegistrationAttempts)) exceeded, giving up")
                lastSetupFailureMessage = "Ping Warden could not register its helper after several attempts. Open Settings → Advanced and click Repair, or check \(SystemSettingsCopy.loginItemsPath)."
                abandonEnable(operationID)
                completion?(false)
                return
            }

            isRegisteringHelper = true
            // The protection caller reports this failure in its own surface.
            registerHelper(presentsErrors: false) { [weak self] success in
                guard let self else { return }
                self.isRegisteringHelper = false
                guard self.isCurrentProtectionOperation(operationID) else {
                    completion?(false)
                    return
                }
                if success && self.helperIsEnabledNow {
                    // Reset attempts on success
                    self.stateLock.lock()
                    self._registrationAttempts = 0
                    self.stateLock.unlock()
                    self.startMonitoring(
                        operationID: operationID,
                        persistUserPreference: persistUserPreference,
                        completion: completion
                    )
                } else {
                    self.abandonEnable(operationID)
                    completion?(false)
                }
            }
            return
        }

        // Ensure XPC connection; connectXPC() resets the retry counter
        // internally once the helper answers a validation ping.
        if xpcConnection == nil {
            connectXPC()
        }

        recordCommandFailure(nil)
        let request = EnableRequest(
            operationID: operationID,
            persistUserPreference: persistUserPreference,
            completion: completion
        )
        let didComplete = LockedValue(false)
        let claimCompletion: @Sendable () -> Bool = {
            didComplete.withValue { completed in
                guard !completed else { return false }
                completed = true
                return true
            }
        }
        // A timeout and an XPC error on this command both mean the helper
        // never confirmed it.
        let failUnanswered: @Sendable () -> Void = { [weak self] in
            guard claimCompletion() else { return }
            guard let self else {
                request.finish(false)
                return
            }
            if self.pendingEnable === request {
                self.pendingEnable = nil
            }
            guard self.isCurrentProtectionOperation(operationID) else {
                self.notifyStateChange()
                request.finish(false)
                return
            }
            log.error("The helper did not confirm enabling Ping Protection")
            self.recordCommandTimeout()
            let failure = self.lastCommandFailure
            // XPC preserves message order. Queueing a compensating enable-AWDL
            // command keeps a timed-out transient request from leaving AWDL
            // blocked without a session or visible owner.
            self.stopMonitoring(persistUserPreference: false, compensating: true, completion: nil)
            self.recordCommandFailure(failure)
            PingWardenPreferences.shared.effectiveMonitoringEnabled = false
            self.notifyStateChange()
            request.finish(false)
        }

        // Send command to disable AWDL
        guard let proxy = getHelperProxy(onError: { [weak self] error in
            self?.recordCommandFailure(.rejected(code: (error as NSError).code))
            DispatchQueue.main.async { failUnanswered() }
        }) else {
            log.error("Failed to get helper proxy")
            recordCommandFailure(.noConnection)
            abandonEnable(operationID)
            PingWardenPreferences.shared.effectiveMonitoringEnabled = false
            notifyStateChange()
            request.finish(false)
            return
        }

        log.info("Sending setAWDLEnabled(false) via XPC...")
        pendingEnable = request
        notifyStateChange()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            failUnanswered()
        }

        proxy.setAWDLEnabled(false, reply: { [weak self] success in
            guard let monitor = self else { return }
            DispatchQueue.main.async {
                // Even a reply that arrives after the deadline proves the
                // helper answers.
                monitor.helperResponded()
                guard claimCompletion() else { return }
                if monitor.pendingEnable === request {
                    monitor.pendingEnable = nil
                }
                guard monitor.isCurrentProtectionOperation(operationID) else {
                    log.info("Ignoring stale enable-protection reply")
                    monitor.notifyStateChange()
                    request.finish(false)
                    return
                }
                if success {
                    monitor.recordCommandFailure(nil)
                    monitor.isMonitoring = true
                    if request.persistUserPreference {
                        PingWardenPreferences.shared.isMonitoringEnabled = true
                    }
                    PingWardenPreferences.shared.effectiveMonitoringEnabled = true
                    PingWardenPreferences.shared.lastKnownState = "down"
                    monitor.notifyStateChange()
                    log.info("✅ AWDL monitoring started")
                    request.finish(true)
                } else {
                    log.error("❌ Failed to disable AWDL")
                    monitor.recordCommandFailure(.declined)
                    monitor.abandonEnable(operationID)
                    PingWardenPreferences.shared.effectiveMonitoringEnabled = false
                    monitor.notifyStateChange()
                    request.finish(false)
                }
            }
        })
    }

    /// A first enable that failed leaves nothing pending, so quit and Off
    /// need not treat it as protection that might still land.
    private func abandonEnable(_ operationID: UInt64) {
        stateLock.lock()
        if operationID == _protectionOperationGeneration, !_isMonitoring {
            _desiredProtectionEnabled = false
        }
        stateLock.unlock()
    }

    /// Stop monitoring - sends command to helper via XPC
    func stopMonitoring(
        persistUserPreference: Bool = true,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        stopMonitoring(
            persistUserPreference: persistUserPreference,
            compensating: false,
            completion: completion
        )
    }

    /// `compensating` marks the stop an unanswered enable queues behind
    /// itself. It is housekeeping, not a command anyone waits on, so it must
    /// not keep the menu saying "Turning On" after that enable has failed.
    private func stopMonitoring(
        persistUserPreference: Bool,
        compensating: Bool,
        completion: (@Sendable (Bool) -> Void)?
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopMonitoring(
                    persistUserPreference: persistUserPreference,
                    compensating: compensating,
                    completion: completion
                )
            }
            return
        }
        let operationID = beginProtectionOperation(enabled: false)
        log.info("┌─────────────────────────────────────────────────────┐")
        log.info("│ stopMonitoring() called                             │")
        log.info("└─────────────────────────────────────────────────────┘")

        if xpcConnection == nil {
            connectXPC()
        }

        recordCommandFailure(nil)
        let didComplete = LockedValue(false)
        let claimCompletion: @Sendable () -> Bool = { [weak self] in
            let claimed = didComplete.withValue { completed in
                guard !completed else { return false }
                completed = true
                return true
            }
            if claimed, !compensating {
                self?.pendingStopCount -= 1
            }
            return claimed
        }
        let failUnanswered: @Sendable () -> Void = { [weak self] in
            guard claimCompletion() else { return }
            guard let self, self.isCurrentProtectionOperation(operationID) else {
                self?.notifyStateChange()
                completion?(false)
                return
            }
            log.error("The helper did not confirm disabling Ping Protection")
            self.recordCommandTimeout()
            PingWardenPreferences.shared.lastKnownState = "unknown"
            self.notifyStateChange()
            completion?(false)
        }

        guard let proxy = getHelperProxy(onError: { [weak self] error in
            self?.recordCommandFailure(.rejected(code: (error as NSError).code))
            DispatchQueue.main.async { failUnanswered() }
        }) else {
            log.warning("No helper proxy - cannot confirm Ping Protection stopped")
            recordCommandFailure(.noConnection)
            PingWardenPreferences.shared.lastKnownState = "unknown"
            notifyStateChange()
            completion?(false)
            return
        }

        log.info("Sending setAWDLEnabled(true) via XPC...")
        if !compensating {
            pendingStopCount += 1
            notifyStateChange()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            failUnanswered()
        }

        proxy.setAWDLEnabled(true, reply: { [weak self] success in
            guard let monitor = self else { return }
            DispatchQueue.main.async {
                monitor.helperResponded()
                guard monitor.isCurrentProtectionOperation(operationID) else {
                    log.info("Ignoring stale disable-protection reply")
                    if claimCompletion() {
                        monitor.notifyStateChange()
                        completion?(false)
                    }
                    return
                }
                // Unlike the enable path, apply the state change even when a
                // timeout already claimed completion. The stop command is the
                // last message in flight, so a late success is the truth about
                // the radio; discarding it left _isMonitoring stuck true while
                // AirDrop was already restored. Completion is still reported
                // at most once.
                let reportCompletion = claimCompletion()
                if success {
                    monitor.recordCommandFailure(nil)
                    monitor.isMonitoring = false
                    if persistUserPreference {
                        PingWardenPreferences.shared.isMonitoringEnabled = false
                    }
                    PingWardenPreferences.shared.effectiveMonitoringEnabled = false
                    PingWardenPreferences.shared.lastKnownState = "up"
                    monitor.notifyStateChange()
                    log.info("✅ AWDL monitoring stopped - AirDrop/Handoff available")
                } else {
                    log.error("❌ Failed to enable AWDL")
                    monitor.recordCommandFailure(.declined)
                    PingWardenPreferences.shared.lastKnownState = "unknown"
                    monitor.notifyStateChange()
                }
                guard reportCompletion else { return }
                completion?(success)
            }
        })
    }

    func setProtectionEnabled(
        _ enabled: Bool,
        persistUserPreference: Bool = true
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            if enabled {
                startMonitoring(persistUserPreference: persistUserPreference) { success in
                    continuation.resume(returning: success)
                }
            } else {
                stopMonitoring(persistUserPreference: persistUserPreference) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Perform a health check on the helper.
    /// Must be called from a background thread — uses synchronous semaphore waits.
    func performHealthCheck() -> (isHealthy: Bool, message: String) {
        assert(!Thread.isMainThread, "performHealthCheck must not be called on the main thread")
        log.info("Performing health check...")

        // Check 1: Is helper registered?
        guard helperIsEnabledNow else {
            log.info("Health check: Helper not registered")
            return (false, "The helper is not set up.")
        }

        // Check 2: Can we connect via XPC?
        if xpcConnection == nil {
            connectXPC()
        }

        // Check 3: Query helper status with proper timeout handling. An XPC
        // error signals at once, so a helper that refuses the connection is
        // reported as rejecting it rather than after a timeout.
        let helperStatus = LockedValue("Unknown")
        let helperVersion = LockedValue("Unknown")
        let rejection = LockedValue<HelperCommandFailure?>(nil)
        var statusAnswered = false
        var versionAnswered = false
        let statusSemaphore = DispatchSemaphore(value: 0)
        let versionSemaphore = DispatchSemaphore(value: 0)

        let statusProxy = getHelperProxy(onError: { error in
            rejection.withValue { $0 = .rejected(code: (error as NSError).code) }
            statusSemaphore.signal()
        })
        guard let statusProxy else {
            log.info("Health check: Cannot connect to helper")
            return (false, "No connection to the helper could be made.")
        }
        statusProxy.getAWDLStatus(reply: { status in
            helperStatus.withValue { $0 = status }
            statusSemaphore.signal()
        })
        if statusSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
            log.warning("Health check: getAWDLStatus timed out")
        } else if rejection.withValue({ $0 }) == nil {
            statusAnswered = true
        }

        // A rejected connection is gone; asking it again would only wait.
        if rejection.withValue({ $0 }) == nil, let versionProxy = getHelperProxy(onError: { error in
            rejection.withValue { $0 = .rejected(code: (error as NSError).code) }
            versionSemaphore.signal()
        }) {
            versionProxy.getVersion(reply: { version in
                helperVersion.withValue { $0 = version }
                versionSemaphore.signal()
            })
            if versionSemaphore.wait(timeout: .now() + 2.0) == .timedOut {
                log.warning("Health check: getVersion timed out")
            } else if rejection.withValue({ $0 }) == nil {
                versionAnswered = true
            }
        }

        if !statusAnswered && !versionAnswered {
            let failure = rejection.withValue { $0 } ?? .timedOut
            recordConnectionFailure(failure)
            return (false, "The helper did not respond: \(failure.diagnosticDescription).")
        }
        helperResponded()

        // Check 4: Check actual AWDL interface status
        let awdlStatus = getAWDLInterfaceStatus()
        log.debug("AWDL interface status: \(awdlStatus)")

        let verdict = HelperRecovery.interfaceHealth(
            protectionRequested: isMonitoring,
            interfaceUp: HelperRecovery.interfaceIsUp(flagsLine: awdlStatus)
        )
        guard verdict.isHealthy else {
            log.warning("Health check: AWDL is UP despite monitoring being active")
            return (false, verdict.summary)
        }

        let finalHelperVersion = helperVersion.withValue { $0 }
        let message = "The helper answered (version \(finalHelperVersion)). \(verdict.summary)"
        log.info("Health check: \(message)")
        return (true, message)
    }
    
    /// Get the AWDL intervention count from the helper
    /// Returns attempts to turn off AWDL, including failed writes.
    func getInterventionCount(completion: @escaping @Sendable (Int?) -> Void) {
        // Polled every few seconds, so a missing connection is routine here
        // and is logged at debug level rather than as a warning per poll.
        guard let proxy = getHelperProxy(logsMissingConnection: false) else {
            log.debug("Cannot get intervention count: No helper proxy")
            completion(nil)
            return
        }
        
        proxy.getAWDLInterventionCount(reply: { count in
            DispatchQueue.main.async {
                completion(Int(count))
            }
        })
    }

    /// Current awdl0 interface flags/status for diagnostics.
    func currentAWDLInterfaceStatus() -> String {
        getAWDLInterfaceStatus()
    }
    
    /// Reset the intervention counter in the helper
    func resetInterventionCount(completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        guard let proxy = getHelperProxy() else {
            log.warning("Cannot reset intervention count: No helper proxy")
            completion(false)
            return
        }
        
        proxy.resetAWDLInterventionCount(reply: { success in
            DispatchQueue.main.async {
                if success {
                    log.info("Intervention counter reset successfully")
                }
                completion(success)
            }
        })
    }

    // MARK: - XPC Connection Management

    private func beginProtectionOperation(enabled: Bool) -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        _protectionOperationGeneration &+= 1
        _desiredProtectionEnabled = enabled
        return _protectionOperationGeneration
    }

    private func isCurrentProtectionOperation(_ operationID: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operationID == _protectionOperationGeneration
    }

    /// Atomically increment the XPC retry counter and return the new value.
    /// Using a single locked read-modify-write avoids the race window that a
    /// `xpcRetryCount += 1` through the property accessor would open between
    /// the read and the write.
    @discardableResult
    private func incrementXPCRetryCount() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        _xpcRetryCount += 1
        return _xpcRetryCount
    }

    /// Connect to helper via XPC. `onValidated` receives, on the main queue,
    /// whether the helper answered the connection's validation request.
    private func connectXPC(onValidated: (@Sendable (Bool) -> Void)? = nil) {
        log.debug("Connecting to XPC service: \(self.xpcServiceName)")

        // Use .privileged for daemon registered via SMAppService
        // This is required because the daemon runs as root
        let connection = NSXPCConnection(machServiceName: xpcServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PingWardenHelperProtocol.self)
        let connectionID = ObjectIdentifier(connection)

        connection.interruptionHandler = { [weak self] in
            log.warning("XPC connection interrupted")
            let monitor = self
            DispatchQueue.main.async {
                monitor?.handleXPCInterruption(for: connectionID)
            }
        }

        connection.invalidationHandler = { [weak self] in
            log.warning("XPC connection invalidated")
            let monitor = self
            DispatchQueue.main.async {
                monitor?.handleXPCInvalidation(for: connectionID)
            }
        }

        connection.activate()

        stateLock.lock()
        let previousConnection = _xpcConnection
        _xpcConnection = connection
        _confirmedMonitoring = false
        stateLock.unlock()

        previousConnection?.invalidate()

        log.info("XPC connection activated")

        // Validate connection asynchronously to avoid blocking UI paths.
        // The retry counter is reset only here, once the helper has actually
        // answered — activate() succeeding locally proves nothing about the
        // daemon. Resetting after activate() would let a dead helper produce
        // an infinite reconnect loop that never trips the max-retry cap.
        validateXPCConnection { [weak self] isValid in
            let monitor = self
            DispatchQueue.main.async {
                // Any reply proves the daemon answers, even one arriving on a
                // connection that has since been replaced.
                defer { onValidated?(isValid) }
                guard let monitor,
                      monitor.xpcConnection.map(ObjectIdentifier.init) == connectionID else { return }
                guard isValid else {
                    // A replacement that never answers would otherwise hold
                    // a protection request open forever: no invalidation
                    // arrives, so the bounded retry never runs and a session
                    // waits on it indefinitely. Count it as a dropped
                    // connection so the retry cap still applies.
                    if monitor.isMonitoringRequested {
                        log.warning("Helper did not answer on a connection that carries a protection request")
                        monitor.handleXPCInvalidation(for: connectionID)
                    }
                    return
                }
                monitor.xpcRetryCount = 0
                monitor.reassertMonitoringStateIfNeeded()
            }
        }
    }

    /// Validate XPC connection is actually working. An XPC error on the
    /// request completes at once instead of waiting out the timeout, so a
    /// helper that refuses the connection is reported without a delay.
    private func validateXPCConnection(completion: (@Sendable (Bool) -> Void)? = nil) {
        let didComplete = LockedValue(false)

        let finish: @Sendable (Bool) -> Bool = { isValid in
            let shouldFinish = didComplete.withValue { value in
                guard !value else { return false }
                value = true
                return true
            }
            guard shouldFinish else { return false }
            completion?(isValid)
            return true
        }

        guard let proxy = getHelperProxy(onError: { [weak self] error in
            let failure = HelperCommandFailure.rejected(code: (error as NSError).code)
            self?.recordConnectionFailure(failure)
            if finish(false) {
                log.warning("XPC validation: \(failure.diagnosticDescription, privacy: .public)")
            }
        }) else {
            log.warning("XPC validation: No proxy available")
            recordConnectionFailure(.noConnection)
            completion?(false)
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + helperReplyTimeout) { [weak self] in
            if finish(false) {
                self?.recordConnectionFailure(.timedOut)
                log.warning("XPC validation: Connection timeout - helper may not be running")
            }
        }

        proxy.getVersion(reply: { [weak self] version in
            if version.isEmpty {
                log.warning("XPC validation: Invalid response from helper")
                _ = finish(false)
            } else {
                log.debug("XPC validation: Connection verified successfully")
                self?.recordConnectionFailure(nil)
                self?.helperResponded()
                _ = finish(true)
            }
        })
    }

    /// Why the most recent connection check failed; `nil` after it answered.
    var lastConnectionFailure: HelperCommandFailure? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastConnectionFailure
    }

    private func recordConnectionFailure(_ failure: HelperCommandFailure?) {
        stateLock.lock()
        _lastConnectionFailure = failure
        stateLock.unlock()
    }

    private func reassertMonitoringStateIfNeeded() {
        // Runs on the same main queue as start/stop so a pending Off command
        // cannot be followed by a reconnect's stale enable command.
        dispatchPrecondition(condition: .onQueue(.main))
        let (shouldReassert, operationID) = withProtectionOperationState()
        guard shouldReassert, LicenseManager.launchGateAllowsProtection else {
            return
        }

        guard let proxy = getHelperProxy() else {
            log.warning("Skipping reassert: helper proxy unavailable")
            return
        }

        log.info("Reasserting AWDL blocking state after XPC reconnect")
        proxy.setAWDLEnabled(false, reply: { [weak self] success in
            guard let monitor = self else { return }
            DispatchQueue.main.async {
                monitor.helperResponded()
                // A stopMonitoring() may have raced the reassert; don't
                // stamp "protection on" state over the user's fresh stop.
                guard monitor.isCurrentProtectionOperation(operationID), monitor.isMonitoring else {
                    log.info("Skipping reassert completion: monitoring was stopped meanwhile")
                    return
                }
                if success {
                    monitor.stateLock.lock()
                    monitor._confirmedMonitoring = true
                    monitor.stateLock.unlock()
                    PingWardenPreferences.shared.effectiveMonitoringEnabled = true
                    PingWardenPreferences.shared.lastKnownState = "down"
                    monitor.notifyStateChange()
                } else {
                    // The helper answered and refused, so no retry will
                    // change the outcome. Give the request up rather than
                    // leave it reconnecting forever with a session waiting.
                    log.error("Failed to reassert AWDL blocking state after reconnect")
                    monitor.stateLock.lock()
                    monitor._isMonitoring = false
                    monitor._confirmedMonitoring = false
                    monitor._desiredProtectionEnabled = false
                    monitor.stateLock.unlock()
                    PingWardenPreferences.shared.effectiveMonitoringEnabled = false
                    PingWardenPreferences.shared.lastKnownState = "unknown"
                    monitor.notifyStateChange()
                    monitor.reportAutomatedError(ProtectionFailureCopy.restoreAfterReconnectFailed)
                }
            }
        })
    }

    private func withProtectionOperationState() -> (Bool, UInt64) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (_isMonitoring && _desiredProtectionEnabled, _protectionOperationGeneration)
    }

    /// Handle XPC interruption (temporary disconnect)
    private func handleXPCInterruption(for connectionID: ObjectIdentifier) {
        // A restarted helper has lost its protection intent. Rebuild and
        // validate the connection so the normal bounded recovery path reapplies
        // the current request, even when there was no failed in-flight call.
        handleXPCInvalidation(for: connectionID)
    }

    /// Handle XPC invalidation (permanent disconnect)
    private func handleXPCInvalidation(for invalidatedConnectionID: ObjectIdentifier? = nil) {
        // Prevent re-entrant handling
        stateLock.lock()
        // Idempotency: a single helper drop fires BOTH the connection's
        // invalidationHandler and any in-flight remoteObjectProxyWithErrorHandler.
        // Each arrives as its own main-queue block, so `_isHandlingInvalidation`
        // (reset via defer before the second block runs) cannot dedupe across
        // them. If the connection was already torn down by the first handler,
        // the second must not run again and burn a second XPC retry slot —
        // which would surface "Lost connection" after 2 drops instead of 3.
        if invalidatedConnectionID != nil, _xpcConnection == nil {
            stateLock.unlock()
            log.debug("Ignoring duplicate XPC invalidation; connection already torn down")
            return
        }
        if let invalidatedConnectionID,
           let currentConnection = _xpcConnection,
           ObjectIdentifier(currentConnection) != invalidatedConnectionID {
            stateLock.unlock()
            log.debug("Ignoring stale XPC invalidation from a replaced connection")
            return
        }

        if _isHandlingInvalidation {
            stateLock.unlock()
            log.debug("Already handling XPC invalidation, skipping")
            return
        }
        _isHandlingInvalidation = true
        let abandonedConnection = _xpcConnection
        _xpcConnection = nil
        _confirmedMonitoring = false
        // Replies from the interrupted connection cannot confirm new state.
        _protectionOperationGeneration &+= 1
        let reconnectOperationID = _protectionOperationGeneration
        let wasMonitoring = _isMonitoring
        stateLock.unlock()

        // When this path is reached from a proxy error handler (not the
        // connection's own invalidationHandler), the connection object is
        // still live in the XPC runtime. Invalidate it explicitly or it —
        // and its mach resources and handler blocks — leak for the app's
        // lifetime. invalidate() is an idempotent no-op on an
        // already-invalidated connection.
        abandonedConnection?.invalidate()

        if wasMonitoring {
            PingWardenPreferences.shared.effectiveMonitoringEnabled = false
            notifyStateChange()
        }

        defer {
            stateLock.lock()
            _isHandlingInvalidation = false
            stateLock.unlock()
        }

        // If we were monitoring, try to reconnect with exponential backoff.
        // Snapshot the new retry count from a single atomic increment and use
        // the local for every read below, so we never see a torn value.
        if wasMonitoring, isRepairingHelper {
            // A repair unregisters the helper on purpose, so drops during it
            // are expected. Reconnecting mid-repair would race the new
            // registration, and exhausting would announce a lost connection
            // the repair is about to fix. The repair settles this when it ends.
            log.info("Deferring XPC reconnect until the helper repair finishes")
            stateLock.lock()
            _reconnectDeferredForRepair = true
            stateLock.unlock()
        } else if wasMonitoring {
            let currentRetry = incrementXPCRetryCount()
            if currentRetry <= maxXPCRetries {
                let delay = XPCReconnectPolicy.delayForAttempt(currentRetry)
                log.info("Attempting XPC reconnect in \(delay)s (attempt \(currentRetry)/\(self.maxXPCRetries))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          self.isCurrentProtectionOperation(reconnectOperationID),
                          self.isMonitoringRequested,
                          self.xpcConnection == nil else { return }
                    self.connectXPC()
                }
            } else {
                log.error("Max XPC retry attempts exceeded")
                stateLock.lock()
                _isMonitoring = false
                _desiredProtectionEnabled = false
                stateLock.unlock()
                PingWardenPreferences.shared.effectiveMonitoringEnabled = false
                notifyStateChange()
                // Reconnects run without anyone asking, often mid-game, so
                // this is published where errors already show, not as an alert.
                reportAutomatedError(ProtectionFailureCopy.lostHelperConnection)
            }
        } else {
            PingWardenPreferences.shared.effectiveMonitoringEnabled = false
            notifyStateChange()
        }
    }

    /// Get the helper proxy for making XPC calls (thread-safe)
    /// Uses remoteObjectProxyWithErrorHandler to properly handle XPC errors.
    /// `onError` runs on the XPC queue before the connection is torn down,
    /// so a caller waiting on a reply can finish at once instead of timing out.
    private func getHelperProxy(
        logsMissingConnection: Bool = true,
        onError: (@Sendable (Error) -> Void)? = nil
    ) -> PingWardenHelperProtocol? {
        // Get connection under lock to avoid TOCTOU race
        stateLock.lock()
        let currentConnection = _xpcConnection
        stateLock.unlock()

        guard let xpc = currentConnection else {
            if logsMissingConnection {
                log.warning("No XPC connection available")
            }
            return nil
        }

        let xpcID = ObjectIdentifier(xpc)
        return xpc.remoteObjectProxyWithErrorHandler { [weak self] error in
            log.error("XPC proxy error: \(error.localizedDescription)")
            onError?(error)
            let monitor = self
            DispatchQueue.main.async {
                monitor?.handleXPCInvalidation(for: xpcID)
            }
        } as? PingWardenHelperProtocol
    }

    // MARK: - Registration Polling

    /// Poll for registration status change with timeout.
    /// Timer state and the pending completion are main-thread confined:
    /// callers can reach this from any thread (the singleton's init runs on
    /// whichever thread first touches `shared`), and a Timer scheduled on a
    /// background thread's never-spun run loop would simply never fire.
    private func startPollingForRegistration(
        presentsErrors: Bool,
        completion: (@Sendable (Bool) -> Void)?
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startPollingForRegistration(presentsErrors: presentsErrors, completion: completion)
            }
            return
        }

        log.debug("Starting registration polling (timeout: \(self.registrationTimeoutSeconds)s)...")

        // A superseded poll must still deliver its completion — callers
        // (e.g. startMonitoring's isRegisteringHelper flag) wait on it.
        finishRegistrationPolling(success: false, reason: "superseded by a new registration poll")
        pendingRegistrationCompletion = completion
        pendingRegistrationPresentsErrors = presentsErrors

        // Set up timeout timer
        registrationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: registrationTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            log.warning("Registration polling timed out after \(self.registrationTimeoutSeconds)s")
            self.reportSetupFailure(
                "Ping Warden did not get approval in time. Allow Ping Warden in \(SystemSettingsCopy.loginItemsPath), then try again.",
                title: "Helper Approval Timed Out",
                presentsErrors: self.pendingRegistrationPresentsErrors
            )
            self.finishRegistrationPolling(success: false, reason: "timed out")
        }

        // Set up polling timer
        registrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let status = self.refreshHelperStatus()
            log.debug("Polling: status = \(self.statusDescription(status))")

            switch status {
            case .enabled:
                log.info("✅ Helper registration approved")
                self.connectXPC()
                self.finishRegistrationPolling(success: true, reason: "approved")

            case .notRegistered:
                log.info("❌ Helper registration denied")
                self.finishRegistrationPolling(success: false, reason: "denied")

            case .requiresApproval, .notFound:
                // Keep polling
                break

            @unknown default:
                break
            }
        }
    }

    /// Tear down the polling timers and deliver the pending completion
    /// exactly once. Main-thread only.
    private func finishRegistrationPolling(success: Bool, reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        registrationTimer?.invalidate()
        registrationTimer = nil
        registrationTimeoutTimer?.invalidate()
        registrationTimeoutTimer = nil

        guard let completion = pendingRegistrationCompletion else { return }
        pendingRegistrationCompletion = nil
        log.debug("Registration polling finished (\(reason, privacy: .public))")
        completion(success)
    }

    // MARK: - Helper Methods

    private func notifyStateChange() {
        // Observers usually re-read the registration next, and a state change
        // is the likeliest moment for it to have changed.
        invalidateHelperStatus()
        // Snapshot under the registry's own lock, then deliver outside it so
        // observers may freely call back into add/remove during their callback.
        let observers = stateObservers.snapshot()
        DispatchQueue.main.async {
            observers.forEach { $0() }
            NotificationCenter.default.post(name: .awdlMonitorStateChanged, object: nil)
        }
    }

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
        // Discard stderr so its pipe buffer can never fill up and block ifconfig.
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            // Read until EOF first; the pipe closes when the subprocess exits,
            // so the read unblocks at the same moment waitUntilExit would. The
            // reverse order (wait, then read) can deadlock if a subprocess
            // ever writes enough output to fill the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
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

    /// Record the failure before the caller's completion runs when already on
    /// main, so a caller reading `lastSetupFailureMessage` sees it.
    private func reportSetupFailureOnMain(_ message: String, title: String, presentsErrors: Bool) {
        if Thread.isMainThread {
            reportSetupFailure(message, title: title, presentsErrors: presentsErrors)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reportSetupFailure(message, title: title, presentsErrors: presentsErrors)
            }
        }
    }

    /// Record a setup or repair failure for callers that show it themselves,
    /// and raise an alert only when the caller asked for one. Main thread.
    private func reportSetupFailure(_ message: String, title: String, presentsErrors: Bool) {
        lastSetupFailureMessage = message
        if presentsErrors {
            showError(message, title: title)
        } else {
            log.error("Setup failure reported to caller: \(message, privacy: .public)")
        }
    }

    /// Show error alert. Reserved for setup the person started from a
    /// surface that cannot show the failure itself; protection commands and
    /// automated paths report through their callers instead.
    private func showError(_ message: String, title: String) {
        log.error("Showing error: \(message)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
