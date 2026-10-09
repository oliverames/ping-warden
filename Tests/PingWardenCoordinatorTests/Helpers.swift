extension PingWardenMonitor {
    func harnessFastReplies() {
        helperReplyTimeout = 0.2
        helperRetryDelay = 0.05
    }
    func harnessDefaultReplies() {
        helperReplyTimeout = 2.0
        helperRetryDelay = 1.0
    }
    /// Ordering tests hold a version probe through bounded waits for a newer
    /// action. Keep that probe alive without changing command timeouts or
    /// disabling the validation deadline.
    func harnessHeldProbeReplies() {
        helperReplyTimeout = 10.0
    }
    /// Forget every connection and request. Old connections' timers see a
    /// newer generation and complete quietly.
    func harnessReset() {
        stateLock.lock()
        _protectionOperationGeneration &+= 1
        _isMonitoring = false
        _confirmedMonitoring = false
        _desiredProtectionEnabled = false
        _xpcConnection = nil
        _xpcRetryCount = 0
        _lastCommandFailure = nil
        _lastConnectionFailure = nil
        _isRepairingHelper = false
        _isRegisteringHelper = false
        _reconnectDeferredForRepair = false
        stateLock.unlock()
        pendingEnable = nil
        pendingStopCount = 0
        repairCompletions = []
        defersProtectionReassertion = false
        lastSetupFailureMessage = nil
    }
    var harnessConnection: NSXPCConnection? { _xpcConnection }
    var harnessRetries: Int { _xpcRetryCount }
    func harnessSetRetries(_ count: Int) {
        stateLock.lock()
        _xpcRetryCount = count
        stateLock.unlock()
    }
}
extension ProtectionExperienceCoordinator {
    func harnessReset() {
        actionGeneration += 1
        transition = .idle
        transitionOwner = actionGeneration
        lastError = nil
        silenceMessage = nil
        helperSilent = false
        helperRepairTask = nil
        lastAutomaticRetry = nil
        isTerminating = false
        gameModeActive = false
        requestedSessionTrigger = nil
        clearPause()
    }
    func harnessSetPause(until date: Date) {
        pauseUntil = date
    }
}

let upLine = "awdl0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
let downLine = "awdl0: flags=8862<BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
let xpcConnectionInvalid = 4099

func spin(_ seconds: Double = 0.03) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
}
/// The monitor's current connection, waiting for one to exist (or, with
/// `previous`, for a replacement) rather than for a fixed delay that a
/// loaded machine can outrun. A timed-out wait returns whatever is current
/// so the calling check reports the failure.
func awaitConnection(replacing previous: NSXPCConnection? = nil, timeout: Double = 3) -> NSXPCConnection {
    spin(until: {
        guard let current = monitor.harnessConnection else { return false }
        return previous.map { current !== $0 } ?? true
    }, timeout: timeout)
    guard let connection = monitor.harnessConnection else {
        preconditionFailure("harness: the monitor never created a connection")
    }
    return connection
}

/// Waits until the fixture helper has received at least `count` protection
/// commands.
func awaitCommands(on connection: NSXPCConnection, count: Int = 1, timeout: Double = 3) {
    spin(until: { connection.helper.commands.count >= count }, timeout: timeout)
}

/// Waits until the fixture helper has received at least `count` version
/// requests.
func awaitVersionRequests(on connection: NSXPCConnection, count: Int = 1, timeout: Double = 3) {
    spin(until: { connection.helper.versions.count >= count }, timeout: timeout)
}

func spin(until condition: () -> Bool, timeout: Double) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { spin(0.01) }
}
var failures: [String] = []
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message); print("FAIL: " + message) }
    else if ProcessInfo.processInfo.environment["PING_WARDEN_TEST_VERBOSE"] == "1" { print("PASS: " + message) }
}

let monitor = PingWardenMonitor.shared
let coordinator = MainActor.assumeIsolated { ProtectionExperienceCoordinator.shared }
let session = MainActor.assumeIsolated { ProtectedSessionCoordinator.shared }

/// Answer every outstanding command on every connection so no test leaves a
/// reply or timeout behind for the next one.
func settle() {
    for connection in NSXPCConnection.instances {
        while !connection.helper.commands.isEmpty {
            connection.helper.commands.removeFirst().1(true)
        }
        while !connection.helper.versions.isEmpty {
            connection.helper.versions.removeFirst()("fixture-helper")
        }
        connection.helper.states.removeAll()
        connection.helper.statuses.removeAll()
    }
    spin(0.1)
}

@MainActor func resetAll() {
    settle()
    monitor.harnessReset()
    monitor.harnessFastReplies()
    let p = PingWardenPreferences.shared
    p.isMonitoringEnabled = false
    p.effectiveMonitoringEnabled = false
    p.lastKnownState = "unknown"
    p.protectionPauseUntil = nil
    LicenseManager.shared.canEnableProtection = true
    LicenseManager.shared.grandfatherWindowExpired = false
    LicenseManager.launchGateAllowsProtection = true
    SMAppService.fixtureStatus = .enabled
    SMAppService.fixtureAllowsRegistration = false
    SMAppService.statusAfterRegister = .enabled
    SMAppService.onUnregister = nil
    // The fixture status changed behind the monitor's back, as a change in
    // System Settings would; the app re-reads it on activation.
    monitor.refreshHelperStatus()
    SMAppService.registerCalls = 0
    SMAppService.unregisterCalls = 0
    SMAppService.openSettingsCalls = 0
    NSXPCConnection.invalidateWhenUnregistered = false
    FakeHelper.autoReplyVersion = nil
    FakeHelper.answersStatus = true
    HarnessInterface.flagsLine = ""
    session.phase = .idle
    session.activeTrigger = nil
    session.interruptionsNoted = 0
    session.endings = []
    coordinator.harnessReset()
    automatedErrors = []
}
var automatedErrors: [String] = []
// Keep the handler the coordinator installed, and also count each report.
let productionAutomatedErrorHandler = monitor.automatedErrorHandler
monitor.automatedErrorHandler = { message in
    DispatchQueue.main.async { automatedErrors.append(message) }
    productionAutomatedErrorHandler?(message)
}

/// Run a coordinator action and return a box its result lands in.
func launch(_ action: @escaping @MainActor () async -> Bool) -> LockedValue<Bool?> {
    let result = LockedValue<Bool?>(nil)
    Task { @MainActor in
        let value = await action()
        result.withValue { $0 = value }
    }
    return result
}
func launchVoid(_ action: @escaping @MainActor () async -> Void) -> LockedValue<Bool> {
    let done = LockedValue(false)
    Task { @MainActor in
        await action()
        done.withValue { $0 = true }
    }
    return done
}

func launchRepair() -> LockedValue<HelperTestReport?> {
    let result = LockedValue<HelperTestReport?>(nil)
    Task { @MainActor in
        let report = await coordinator.repairHelperConnection()
        result.withValue { $0 = report }
    }
    return result
}

/// Turn protection on through the coordinator with an answering helper.
@MainActor func turnOnThroughCoordinator() -> NSXPCConnection {
    let result = launch { await coordinator.setPersistentProtection(true) }
    let connection = awaitConnection()
    awaitCommands(on: connection)
    connection.helper.versions.forEach { $0("fixture-helper") }
    connection.helper.versions.removeAll()
    connection.helper.commands.removeFirst().1(true)
    spin(until: { result.withValue { $0 } != nil }, timeout: 2)
    precondition(result.withValue { $0 } == true && monitor.isMonitoringActive, "setup failed")
    spin(0.05)
    return connection
}

// Repair fixtures. The monitor validates the app bundle before it rebuilds a
// registration; for this command-line harness Bundle.main is the temporary
// build directory, so the fixture bundle lives there and nowhere else.
func setFixtureHelperBundle(installed: Bool) {
    let contents = URL(fileURLWithPath: Bundle.main.bundlePath).appendingPathComponent("Contents")
    let fileManager = FileManager.default
    guard installed else {
        try? fileManager.removeItem(at: contents)
        return
    }
    try! fileManager.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try! fileManager.createDirectory(at: contents.appendingPathComponent("Library/LaunchDaemons"), withIntermediateDirectories: true)
    fileManager.createFile(
        atPath: contents.appendingPathComponent("MacOS/PingWardenHelper").path,
        contents: Data(),
        attributes: [.posixPermissions: 0o755]
    )
    fileManager.createFile(
        atPath: contents.appendingPathComponent("Library/LaunchDaemons/com.amesvt.pingwarden.helper.plist").path,
        contents: Data()
    )
}
