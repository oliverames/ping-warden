extension PingWardenMonitor {
    func harnessFastReplies() {
        helperReplyTimeout = 0.2
        helperRetryDelay = 0.05
    }
    func harnessDefaultReplies() {
        helperReplyTimeout = 2.0
        helperRetryDelay = 1.0
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
        lastSetupFailureMessage = nil
    }
    var harnessConnection: NSXPCConnection? { _xpcConnection }
    var harnessRetries: Int { _xpcRetryCount }
}
extension ProtectionExperienceCoordinator {
    func harnessReset() {
        actionGeneration += 1
        transition = .idle
        transitionOwner = actionGeneration
        lastError = nil
        silenceMessage = nil
        helperSilent = false
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
func spin(until condition: () -> Bool, timeout: Double) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { spin(0.01) }
}
var failures: [String] = []
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message); print("FAIL: " + message) }
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

/// Turn protection on through the coordinator with an answering helper.
@MainActor func turnOnThroughCoordinator() -> NSXPCConnection {
    let result = launch { await coordinator.setPersistentProtection(true) }
    spin()
    let connection = monitor.harnessConnection!
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
