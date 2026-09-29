extension PingWardenMonitor {
    static func harnessMonitor() -> PingWardenMonitor {
        // In-memory fixture state only. Never reads or writes UserDefaults.
        PingWardenPreferences.shared.isMonitoringEnabled = false
        PingWardenPreferences.shared.effectiveMonitoringEnabled = false
        PingWardenPreferences.shared.lastKnownState = "unknown"
        PingWardenPreferences.shared.protectionPauseUntil = nil
        LicenseManager.launchGateAllowsProtection = true
        SMAppService.fixtureStatus = .enabled
        SMAppService.fixtureAllowsRegistration = false
        SMAppService.fixtureRegistrationError = nil
        SMAppService.fixtureStatusAfterRegistration = .enabled
        SMAppService.settingsOpenCalls = 0
        SMAppService.registerCalls = 0
        SMAppService.unregisterCalls = 0
        FakeHelper.autoReplyVersion = nil
        let monitor = PingWardenMonitor(harness: ())
        // Registration polling runs in fixture time: 20 ms reads, a 200 ms
        // Not Registered grace period, and a 300 ms Login Items handoff.
        monitor.registrationPollInterval = 0.02
        monitor.notRegisteredGraceSeconds = 0.2
        monitor.loginItemsHandoffDelay = 0.3
        monitor.registrationRetryInterval = 0.04
        return monitor
    }
    func harnessFastReplies() {
        helperReplyTimeout = 0.2
        helperRetryDelay = 0.05
    }
    func harnessConnectRequested() -> NSXPCConnection {
        isMonitoring = true
        _desiredProtectionEnabled = true
        connectXPC()
        return _xpcConnection!
    }
    func harnessDispose() {
        _protectionOperationGeneration &+= 1
        _isMonitoring = false
        _desiredProtectionEnabled = false
        _xpcConnection = nil
    }
    func harnessEndRegistration() {
        finishRegistrationPolling(success: false, reason: "fixture cleanup")
    }
    var harnessRetries: Int { _xpcRetryCount }
    var harnessConnection: NSXPCConnection? { _xpcConnection }
    func harnessReassert() { reassertMonitoringStateIfNeeded() }
}
func spin(_ seconds: Double = 0.03) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
}
var failures: [String] = []
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message); print("FAIL: " + message) }
}
func confirmed(_ monitor: PingWardenMonitor) -> NSXPCConnection {
    let connection = monitor.harnessConnectRequested()
    connection.helper.versions.removeFirst()("fixture-helper")
    spin()
    connection.helper.commands.removeFirst().1(true)
    spin()
    check(monitor.isMonitoringActive, "setup must be confirmed")
    return connection
}

// Actual interruption handler and scheduled retry, no in-flight proxy error.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let old = confirmed(monitor)
    old.interruptionHandler?()
    spin()
    check(!monitor.isMonitoringActive && monitor.isMonitoringRequested, "interruption must immediately remove confirmation, retain intent")
    check(monitor.harnessRetries == 1, "interruption/invalidation duplicate must consume one retry")
    old.interruptionHandler?()
    spin()
    check(monitor.harnessRetries == 1, "duplicate interruption must not consume another retry")
    spin(1.05)
    let new = monitor.harnessConnection!
    check(new !== old, "interruption creates a replacement")
    check(!monitor.isMonitoringActive && new.helper.commands.isEmpty, "replacement must validate before reporting protected")
    new.helper.versions.removeFirst()("fixture-helper")
    spin()
    check(new.helper.commands.count == 1 && new.helper.commands[0].0 == false, "validated connection reasserts protection exactly once")
    new.helper.commands.removeFirst().1(true)
    spin()
    check(monitor.isMonitoringActive, "successful reassert restores confirmation")
    old.interruptionHandler?()
    spin()
    check(monitor.harnessConnection === new && monitor.harnessRetries == 0, "late old-connection interruption must preserve replacement")
}

// A fresh stop/pause while a reconnect is pending must supersede it.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let old = confirmed(monitor)
    old.interruptionHandler?()
    spin()
    let count = NSXPCConnection.instances.count
    let completions = LockedValue<[Bool]>([])
    monitor.stopMonitoring(persistUserPreference: false) { value in completions.withValue { $0.append(value) } }
    let off = monitor.harnessConnection!
    check(off.helper.commands.map(\.0) == [true], "stop during reconnect must only request AWDL on")
    off.helper.commands.removeFirst().1(true)
    off.helper.versions.removeFirst()("fixture-helper")
    spin(1.1)
    check(NSXPCConnection.instances.count == count + 1, "stale retry timer must not replace the stop connection")
    check(off.helper.commands.isEmpty && !monitor.isMonitoringActive && !monitor.isMonitoringRequested, "paused/stopped state must not reassert")
    check(completions.withValue { $0 } == [true], "stop completion must fire exactly once")
}

// Old reassert replies cannot confirm a replacement connection.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let old = monitor.harnessConnectRequested()
    old.helper.versions.removeFirst()("fixture-helper")
    spin()
    let staleReply = old.helper.commands.removeFirst().1
    old.interruptionHandler?()
    spin()
    staleReply(true)
    spin()
    check(!monitor.isMonitoringActive && !PingWardenPreferences.shared.effectiveMonitoringEnabled, "stale success must not reconfirm protection")
}

// A lost pending stop replies false exactly once after its bounded timeout.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let old = confirmed(monitor)
    let results = LockedValue<[Bool]>([])
    monitor.stopMonitoring(persistUserPreference: false) { value in results.withValue { $0.append(value) } }
    let staleStop = old.helper.commands.removeFirst().1
    old.interruptionHandler?()
    spin()
    staleStop(true)
    spin(5.1)
    check(results.withValue { $0 } == [false], "interrupted stop completion must not hang or double-complete")
    check(!monitor.isMonitoringActive, "interrupted stop cannot remain confirmed")
}

// A failed latest reassert must clear any earlier confirmation.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let connection = confirmed(monitor)
    monitor.harnessReassert()
    connection.helper.commands.removeFirst().1(false)
    spin()
    check(!monitor.isMonitoringActive, "failed reassert must clear prior confirmation")
}

// A dead replacement helper exhausts exactly three retries and stops.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let initial = confirmed(monitor)
    let baseline = NSXPCConnection.instances.count
    let alerts = NSAlert.messages.count
    let reported = LockedValue<[String]>([])
    monitor.automatedErrorHandler = { message in reported.withValue { $0.append(message) } }
    initial.interruptionHandler?()
    spin()
    for delay in [1.05, 2.05, 4.05] {
        spin(delay)
        guard let replacement = monitor.harnessConnection else { fatalError("expected bounded replacement attempt") }
        check(!monitor.isMonitoringActive, "unvalidated retry cannot be protected")
        replacement.invalidationHandler?()
        spin()
    }
    check(monitor.harnessConnection == nil && !monitor.isMonitoringRequested && !monitor.isMonitoringActive,
          "exhausted retries must leave honest stopped state")
    check(monitor.harnessRetries == 4 && NSXPCConnection.instances.count == baseline + 3,
          "dead helper produces exactly three replacement attempts")
    spin()
    check(reported.withValue { $0 }.count == 1 && reported.withValue { $0 }.first?.contains("Lost connection") == true,
          "exhaustion reports recoverable user error")
    check(reported.withValue { $0 }.first?.contains("click Repair") == true,
          "exhaustion points to Repair, not to restarting the app")
    check(NSAlert.messages.count == alerts, "automated reconnect exhaustion must never raise an alert")
}

// Rechecking a confirmed positive state cannot transiently end a session.
// A later authoritative negative reply must still clear that confirmation.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let connection = confirmed(monitor)
    let observedStates = LockedValue<[Bool]>([])
    let token = monitor.addStateObserver {
        observedStates.withValue { $0.append(monitor.isMonitoringActive) }
    }
    defer { monitor.removeStateObserver(token) }
    monitor.adoptExternallyAppliedMonitoringState(true)
    spin()
    check(monitor.isMonitoringActive && observedStates.withValue { $0 } == [true],
          "same-state notification cannot demote confirmed protection before a delayed helper reply")
    check(connection.helper.commands.isEmpty, "same-state adoption must only query the helper")
    connection.helper.states.removeFirst()(false)
    spin()
    check(monitor.isMonitoringActive && observedStates.withValue { $0.allSatisfy { $0 } },
          "positive confirmation must preserve every active-state notification")
    monitor.adoptExternallyAppliedMonitoringState(true)
    connection.helper.states.removeFirst()(true)
    spin()
    check(!monitor.isMonitoringActive && !monitor.isMonitoringRequested,
          "authoritative negative reply must clear an earlier confirmation")
}

// A repeated ON hint cannot authorize reassertion over an in-flight stop.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let connection = confirmed(monitor)
    monitor.stopMonitoring(persistUserPreference: false)
    monitor.adoptExternallyAppliedMonitoringState(true)
    monitor.harnessReassert()
    check(connection.helper.commands.map(\.0) == [true],
          "same-state notification must preserve the pending stop intent")
}

// Shared defaults may claim protection is active while the helper is off.
// Neither response ordering may issue a command before authoritative state.
for versionFirst in [true, false] {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    monitor.adoptExternallyAppliedMonitoringState(true)
    let connection = monitor.harnessConnection!
    check(monitor.isMonitoringRequested && !monitor.isMonitoringActive,
          "adopted active hint must remain unconfirmed")
    check(connection.helper.commands.isEmpty, "adoption must begin with queries only")
    if versionFirst {
        connection.helper.versions.removeFirst()("fixture-helper")
        spin()
        check(connection.helper.commands.isEmpty,
              "version-before-state must not reassert the untrusted active hint")
        connection.helper.states.removeFirst()(true)
    } else {
        connection.helper.states.removeFirst()(true)
        spin()
        check(!monitor.isMonitoringActive && !monitor.isMonitoringRequested,
              "authoritative off state must replace the provisional hint")
        connection.helper.versions.removeFirst()("fixture-helper")
    }
    spin()
    check(connection.helper.commands.isEmpty,
          "helper-off adoption must never issue a disable-AWDL command in either reply order")
    check(!monitor.isMonitoringActive && !monitor.isMonitoringRequested &&
          !PingWardenPreferences.shared.effectiveMonitoringEnabled,
          "helper-off adoption must end with consistent unprotected state")
}

// A helper that confirms protection still establishes active state in both
// response orders. Any later reassert is based on authenticated helper state.
for versionFirst in [true, false] {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    monitor.adoptExternallyAppliedMonitoringState(true)
    let connection = monitor.harnessConnection!
    if versionFirst {
        connection.helper.versions.removeFirst()("fixture-helper")
        spin()
        check(connection.helper.commands.isEmpty,
              "validated connection alone must not confirm or reassert shared state")
        connection.helper.states.removeFirst()(false)
    } else {
        connection.helper.states.removeFirst()(false)
        spin()
        check(monitor.isMonitoringActive, "helper-confirmed protection must become active")
        connection.helper.versions.removeFirst()("fixture-helper")
    }
    spin()
    check(monitor.isMonitoringActive && monitor.isMonitoringRequested &&
          PingWardenPreferences.shared.effectiveMonitoringEnabled,
          "helper-protected adoption must remain active in either reply order")
    check(connection.helper.commands.allSatisfy { !$0.0 },
          "confirmed protection must never be disabled during adoption")
    for (_, reply) in connection.helper.commands { reply(true) }
    spin()
    check(monitor.isMonitoringActive, "acknowledged reassert must preserve confirmed protection")
}

// An interrupted first activation must complete false exactly once, even with
// a delayed success and its timeout both arriving after the generation changes.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    let results = LockedValue<[Bool]>([])
    monitor.startMonitoring(persistUserPreference: false) { value in results.withValue { $0.append(value) } }
    let connection = monitor.harnessConnection!
    let delayedStart = connection.helper.commands.removeFirst().1
    connection.interruptionHandler?()
    spin()
    delayedStart(true)
    spin(5.1)
    check(results.withValue { $0 } == [false], "interrupted first activation completion must be false exactly once")
    check(!monitor.isMonitoringActive, "delayed activation success must not mark interrupted connection protected")
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
func spin(until condition: () -> Bool, timeout: Double) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { spin(0.01) }
}

// Repair leaves an answering helper's registration alone and reports success
// only once the helper has replied.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    monitor.harnessFastReplies()
    let results = LockedValue<[Bool]>([])
    monitor.repairHelperRegistration { value in results.withValue { $0.append(value) } }
    spin()
    check(results.withValue { $0 }.isEmpty, "repair must wait for the helper's reply")
    NSXPCConnection.instances.last!.helper.versions.removeFirst()("fixture-helper")
    spin()
    check(results.withValue { $0 } == [true], "an answering helper repairs as success exactly once")
    check(SMAppService.unregisterCalls == 0 && SMAppService.registerCalls == 0,
          "an answering helper's registration must never be rebuilt")
}

// The launch probe asks over the existing connection. Replacing it would drop
// a protection command in flight and let its timeout turn protection off.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    monitor.harnessFastReplies()
    let connection = confirmed(monitor)
    let instances = NSXPCConnection.instances.count
    let results = LockedValue<[Bool]>([])
    monitor.confirmHelperResponds { value in results.withValue { $0.append(value) } }
    spin()
    check(NSXPCConnection.instances.count == instances && monitor.harnessConnection === connection,
          "the helper probe must reuse the live connection")
    check(!connection.helper.versions.isEmpty, "the probe must ask over the live connection")
    if !connection.helper.versions.isEmpty { connection.helper.versions.removeFirst()("fixture-helper") }
    spin()
    check(results.withValue { $0 } == [true], "the probe reports the helper's reply once")
    check(monitor.isMonitoringActive && !connection.didInvalidate,
          "probing must leave confirmed protection and its connection intact")
}

// A silent helper is not torn down when the bundle could not register it again.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose() }
    monitor.harnessFastReplies()
    setFixtureHelperBundle(installed: false)
    let alerts = NSAlert.messages.count
    let results = LockedValue<[Bool]>([])
    monitor.repairHelperRegistration { value in results.withValue { $0.append(value) } }
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 3)
    spin()
    check(results.withValue { $0 } == [false], "repair without a valid bundle must fail once")
    check(SMAppService.unregisterCalls == 0, "a registration that cannot be rebuilt must be left in place")
    check(NSAlert.messages.count == alerts + 1 && NSAlert.messages.last?.contains("reinstall") == true,
          "a missing helper bundle tells the user to reinstall")
}

// A registered but silent helper is unregistered, registered again, and
// reported repaired only after the rebuilt helper answers.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    monitor.harnessFastReplies()
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    let results = LockedValue<[Bool]>([])
    monitor.repairHelperRegistration { value in results.withValue { $0.append(value) } }
    spin(until: { SMAppService.registerCalls == 1 }, timeout: 3)
    check(SMAppService.unregisterCalls == 1 && SMAppService.registerCalls == 1,
          "a silent helper's registration must be rebuilt once")
    check(results.withValue { $0 }.isEmpty, "a rebuilt registration still needs a reply before success")
    FakeHelper.autoReplyVersion = "fixture-helper"
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 4)
    spin()
    check(results.withValue { $0 } == [true], "the rebuilt helper's reply completes repair exactly once")
}

// A helper that stays silent after its registration is rebuilt fails repair.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    monitor.harnessFastReplies()
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    let results = LockedValue<[Bool]>([])
    monitor.repairHelperRegistration { value in results.withValue { $0.append(value) } }
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 5)
    spin()
    check(results.withValue { $0 } == [false], "a helper that never answers must not be reported repaired")
    check(SMAppService.unregisterCalls == 1 && SMAppService.registerCalls == 1,
          "repair rebuilds the registration once, not in a loop")
}

// Only Operation not permitted (code 1) in the SMAppService or POSIX domain
// means a daemon awaits approval. Other domains, codes, and English
// descriptions are real failures.
check(PingWardenMonitor.isPendingApprovalError(NSError(domain: "SMAppServiceErrorDomain", code: 1)),
      "SMAppService Operation not permitted means approval is pending")
check(PingWardenMonitor.isPendingApprovalError(NSError(domain: NSPOSIXErrorDomain, code: 1)),
      "POSIX EPERM means approval is pending")
check(!PingWardenMonitor.isPendingApprovalError(NSError(domain: "SMAppServiceErrorDomain", code: 12)),
      "other SMAppService codes are not pending approval")
check(!PingWardenMonitor.isPendingApprovalError(NSError(domain: "FixtureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])),
      "an English description in another domain is not pending approval")

// Registration failures that are not pending approval complete at once.
// Every platform boundary is inert.
for error in [
    NSError(domain: "com.apple.ServiceManagement", code: 10, userInfo: [NSLocalizedDescriptionKey: "Fixture invalid plist"]),
    NSError(domain: "FixtureError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
] {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    SMAppService.fixtureRegistrationError = error
    let results = LockedValue<[Bool]>([])
    let alerts = NSAlert.messages.count
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin()
    check(results.withValue { $0 } == [false], "a failed registration without pending approval completes false once")
    check(SMAppService.settingsOpenCalls == 0, "error text and domains alone must not open Settings")
    check(monitor.lastSetupFailureMessage?.contains(error.localizedDescription) == true,
          "registration failure must retain the actual error for retry guidance")
    check(NSAlert.messages.count == alerts, "a silent registration failure must not show an alert")
}

// Another request can finish registration after our initial status check.
// A documented AlreadyRegistered error must honor the fresh enabled status.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .enabled
    SMAppService.fixtureRegistrationError = NSError(domain: "SMAppServiceErrorDomain", code: 12)
    let results = LockedValue<[Bool]>([])
    let alerts = NSAlert.messages.count
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin()
    check(results.withValue { $0 } == [true], "an already enabled helper completes registration successfully once")
    check(monitor.harnessConnection != nil && !monitor.isMonitoringActive,
          "enabled registration connects but must not claim confirmed protection")
    check(SMAppService.settingsOpenCalls == 0 && SMAppService.registerCalls == 1,
          "already enabled registration neither opens Settings nor retries")
    check(NSAlert.messages.count == alerts && monitor.lastSetupFailureMessage == nil,
          "already enabled registration must not leave a false setup failure")
}

// An approval-pending error that never becomes a registration still ends,
// after the grace period, with the error macOS reported.
for error in [
    NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not permitted"]),
    NSError(domain: NSPOSIXErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture EPERM"])
] {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    SMAppService.fixtureRegistrationError = error
    let results = LockedValue<[Bool]>([])
    let alerts = NSAlert.messages.count
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(0.1)
    check(results.withValue { $0 }.isEmpty, "an approval-pending error waits instead of failing at once")
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [false], "a pending registration that never appears completes false once")
    check(monitor.lastSetupFailureMessage?.contains(error.localizedDescription) == true,
          "the eventual failure keeps the error macOS reported")
    check(SMAppService.settingsOpenCalls == 0, "Login Items opens only for a registration awaiting approval")
    check(NSAlert.messages.count == alerts, "a silent registration failure must not show an alert")
}

// Repair's rebuild: register() right after unregister() is refused with
// Operation not permitted and the status stays Not Registered while the old
// record is removed. A later retry registers without new approval. Observed
// on macOS 27.2 on September 29, 2026 with a signed fixture.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    SMAppService.fixtureRegistrationError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    check(results.withValue { $0 }.isEmpty && SMAppService.registerCalls == 1,
          "a refused re-registration waits instead of failing at once")
    SMAppService.fixtureRegistrationError = nil
    SMAppService.fixtureStatusAfterRegistration = .enabled
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [true], "a retried registration completes once")
    check(SMAppService.registerCalls == 2, "one retry is enough once macOS accepts it")
    check(SMAppService.settingsOpenCalls == 0 && monitor.lastSetupFailureMessage == nil,
          "a retried registration neither opens Login Items nor leaves a failure")
}

// A refusal that persists is retried a bounded number of times.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    SMAppService.fixtureRegistrationError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    spin(0.2)
    check(results.withValue { $0 } == [false], "a persistent refusal completes false once")
    check(SMAppService.registerCalls == 4, "a persistent refusal is retried three times, not in a loop")
}

// A fresh request that registers but never appears is not retried.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(SMAppService.registerCalls == 1, "only a refused registration is retried")
}

// Operation not permitted while macOS shows its approval notification, with
// the status still catching up: wait, then complete once approved.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    SMAppService.fixtureRegistrationError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(0.1)
    SMAppService.fixtureStatus = .requiresApproval
    spin(0.1)
    SMAppService.fixtureStatus = .enabled
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [true], "approval after Operation not permitted completes registration once")
    check(SMAppService.settingsOpenCalls == 0, "approval from the notification needs no Login Items handoff")
    check(monitor.lastSetupFailureMessage == nil, "a completed approval leaves no setup failure")
}

// A fresh registration awaiting approval leaves the first move to macOS's
// notification, then opens Login Items once if approval is still pending.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .requiresApproval
    SMAppService.fixtureRegistrationError = NSError(domain: "FixtureError", code: 99)
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    check(SMAppService.settingsOpenCalls == 0 && results.withValue { $0 }.isEmpty,
          "a fresh registration must not open Login Items over the approval notification")
    spin(0.45)
    check(SMAppService.settingsOpenCalls == 1 && results.withValue { $0 }.isEmpty,
          "approval still pending after the handoff delay opens Login Items once and waits")
    spin(0.2)
    check(SMAppService.settingsOpenCalls == 1, "Login Items opens only once per registration")
    SMAppService.fixtureStatus = .enabled
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [true], "approval must complete registration once")
    check(!monitor.isMonitoringActive, "registration approval alone must not report protection")
}

// Approval granted from the notification before the handoff delay never
// opens Login Items, so a second switch toggle cannot revoke it.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .requiresApproval
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(0.1)
    SMAppService.fixtureStatus = .enabled
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    spin(0.4)
    check(results.withValue { $0 } == [true], "notification approval completes registration once")
    check(SMAppService.settingsOpenCalls == 0, "approval before the handoff delay never opens Login Items")
}

// A registration that was already waiting before this request has no new
// notification, so Login Items opens at once.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .requiresApproval
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    check(SMAppService.settingsOpenCalls == 1 && SMAppService.registerCalls == 0,
          "an existing pending approval opens Login Items without registering again")
    spin(0.45)
    check(SMAppService.settingsOpenCalls == 1, "the entry handoff is not repeated by polling")
}

// A brief Not Registered read while approval is processed is not a failure.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .requiresApproval
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(0.05)
    SMAppService.fixtureStatus = .notRegistered
    spin(0.1)
    SMAppService.fixtureStatus = .requiresApproval
    spin(0.05)
    SMAppService.fixtureStatus = .notRegistered
    spin(0.1)
    SMAppService.fixtureStatus = .enabled
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [true], "transient Not Registered reads must not fail a pending approval")
    check(monitor.lastSetupFailureMessage == nil, "a transient read leaves no setup failure")
}

// A submitted request that remains unregistered is a failed registration,
// with useful retry guidance. It is not evidence that the user denied it.
do {
    let monitor = PingWardenMonitor.harnessMonitor()
    defer { monitor.harnessEndRegistration(); monitor.harnessDispose(); setFixtureHelperBundle(installed: false) }
    setFixtureHelperBundle(installed: true)
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.fixtureStatus = .notRegistered
    SMAppService.fixtureStatusAfterRegistration = .notRegistered
    let results = LockedValue<[Bool]>([])
    monitor.registerHelper(presentsErrors: false) { value in results.withValue { $0.append(value) } }
    spin(until: { !results.withValue { $0 }.isEmpty }, timeout: 1.5)
    check(results.withValue { $0 } == [false], "an unregistered service completes false exactly once")
    check(monitor.lastSetupFailureMessage?.contains("Try setting up Ping Protection again") == true,
          "an unregistered service must leave neutral actionable retry guidance")
    check(SMAppService.settingsOpenCalls == 0 && SMAppService.registerCalls == 1,
          "an unregistered service must neither open Settings nor retry automatically")
}

print("Monitor checks complete. Failures: \(failures.count)")
exit(failures.isEmpty ? 0 : 1)
