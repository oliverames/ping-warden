setvbuf(stdout, nil, _IONBF, 0)
// Each block names the review finding it guards. Every block failed against
// the coordinator and monitor at ed60850 and passes with the fixes.

// B1: Off reaches the helper even when an earlier reading said awdl0 was up.
// A relaunch after a crash can leave the helper enforcing while one
// interface sample catches the instant macOS re-raised awdl0.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.lastKnownState = "down"
    HarnessInterface.flagsLine = upLine
    let first = launch { await coordinator.setPersistentProtection(false) }
    spin()
    let connection = monitor.harnessConnection
    check(connection?.helper.commands.map(\.0) == [true], "B1: Off must send a stop even when awdl0 reads up")
    connection?.helper.commands.removeFirst().1(true)
    spin(until: { first.withValue { $0 } != nil }, timeout: 2)
    check(first.withValue { $0 } == true, "B1: an answered stop reports success")
    check(PingWardenPreferences.shared.lastKnownState == "up", "B1: the helper's reply records awdl0 up")

    // lastKnownState is now "up"; it must not become authority to skip the
    // helper on the next Off.
    HarnessInterface.flagsLine = downLine
    let second = launch { await coordinator.setPersistentProtection(false) }
    spin()
    let secondConnection = monitor.harnessConnection
    check(secondConnection?.helper.commands.map(\.0) == [true],
          "B1: a stored lastKnownState of up must not skip the next stop")
    secondConnection?.helper.commands.removeFirst().1(true)
    spin(until: { second.withValue { $0 } != nil }, timeout: 2)
}

// B1 (B-T5): after the app's own echo, an Off still stops a helper that
// might be enforcing.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    let echo = launchVoid { await coordinator.handleExternallyAppliedProtectionState(true) }
    spin(until: { echo.withValue { $0 } }, timeout: 1)
    // The helper's isAWDLEnabled can report the instant macOS re-raised awdl0.
    if !connection.helper.states.isEmpty { connection.helper.states.removeFirst()(true) }
    spin()
    check(monitor.isMonitoringActive, "B4: the app's own echo must not demote confirmed protection")
    let before = connection.helper.commands.count
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    let offConnection = monitor.harnessConnection
    let stops = (offConnection === connection)
        ? connection.helper.commands.dropFirst(before).map(\.0)
        : (offConnection?.helper.commands.map(\.0) ?? [])
    check(stops == [true], "B1: Off after an echo must send the helper a stop")
    settle()
    spin(until: { off.withValue { $0 } != nil }, timeout: 2)
}

// B1: a helper that refuses the connection, nothing requested, awdl0 up.
// Off succeeds quietly and records the safe state. The XPC error completes
// the stop at once instead of after the five-second deadline.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    PingWardenPreferences.shared.effectiveMonitoringEnabled = true
    PingWardenPreferences.shared.lastKnownState = "unknown"
    HarnessInterface.flagsLine = upLine
    let alerts = NSAlert.messages.count
    let started = Date()
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    let connection = monitor.harnessConnection!
    check(connection.helper.commands.map(\.0) == [true], "B1: Off asks the helper first")
    connection.failProxies(code: xpcConnectionInvalid)
    spin(until: { off.withValue { $0 } != nil }, timeout: 3)
    check(off.withValue { $0 } == true, "B1: a rejected stop with awdl0 up and nothing requested reports success")
    check(Date().timeIntervalSince(started) < 2, "B1: an XPC error must end the wait at once")
    check(!PingWardenPreferences.shared.isMonitoringEnabled
          && !PingWardenPreferences.shared.effectiveMonitoringEnabled
          && PingWardenPreferences.shared.lastKnownState == "up",
          "B1: the quiet success records protection off and awdl0 up")
    check(MainActor.assumeIsolated { coordinator.lastError } == nil, "B1: the quiet success shows no error")
    check(NSAlert.messages.count == alerts, "B1: the quiet success raises no alert")
}

// B1: the same silent helper, with the timeout rather than an XPC error.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    HarnessInterface.flagsLine = upLine
    let alerts = NSAlert.messages.count
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin(until: { off.withValue { $0 } != nil }, timeout: 6)
    check(off.withValue { $0 } == true, "B1: a timed-out stop with awdl0 up and nothing requested reports success")
    check(NSAlert.messages.count == alerts, "B1: a timed-out stop raises no alert")
    check(!PingWardenPreferences.shared.isMonitoringEnabled, "B1: the quiet success clears the saved intent")
}

// B1: a silent helper that may be holding awdl0 down still fails, and the
// copy does not tell someone with a silent helper that quitting helps.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    HarnessInterface.flagsLine = downLine
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    monitor.harnessConnection?.failProxies(code: xpcConnectionInvalid)
    spin(until: { off.withValue { $0 } != nil }, timeout: 3)
    let message = MainActor.assumeIsolated { coordinator.lastError } ?? ""
    check(off.withValue { $0 } == false, "B1: a silent stop with awdl0 down still fails")
    check(message.contains("Repair") && !message.contains("Quit"),
          "B14: a silent-helper Off failure points to Repair, not to quitting")
    check(PingWardenPreferences.shared.isMonitoringEnabled, "B1: a failed Off keeps the saved intent")
}

// B1: with protection requested, a rejected stop is a real failure even if
// awdl0 reads up.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    HarnessInterface.flagsLine = upLine
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    check(connection.helper.commands.map(\.0) == [true], "B1: Off stops confirmed protection")
    connection.failProxies(code: xpcConnectionInvalid)
    spin(until: { off.withValue { $0 } != nil }, timeout: 3)
    check(off.withValue { $0 } == false, "B1: a requested protection's failed stop is never reported as success")
}

// B2 (B-T3): a saved intent with a silent helper. The toggle's title and
// action come from one decision, and the status stops promising progress
// once nothing is in flight.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    MainActor.assumeIsolated { coordinator.noteHelperNotResponding() }
    let presentation = MainActor.assumeIsolated { coordinator.menuPresentation() }
    let action = MainActor.assumeIsolated { coordinator.toggleAction() }
    check(presentation.protectionTitle == action.menuTitle, "B2: the menu title comes from the toggle decision")
    check(action == .turnOff, "B2: with protection wanted, the toggle turns it off")
    check(presentation.statusTitle == "Status: Not Protected, Helper Not Responding",
          "B2: with no command in flight the status is honest, not Turning On")

    // While an enable is in flight the status may say Turning On.
    let enable = launch { await coordinator.setPersistentProtection(true) }
    spin()
    check(MainActor.assumeIsolated { coordinator.menuPresentation().statusTitle } == "Status: Turning On Protection",
          "B2: Turning On appears while the command is pending")
    settle()
    spin(until: { enable.withValue { $0 } != nil }, timeout: 2)
    check(MainActor.assumeIsolated { coordinator.toggleAction() } == .turnOff, "B2: protection on means the toggle turns it off")
}

// B2: the monitor's own launch restore counts as a command in flight.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    monitor.startMonitoring(persistUserPreference: false)
    spin()
    check(MainActor.assumeIsolated { coordinator.menuPresentation().statusTitle } == "Status: Turning On Protection",
          "B2: the init restore's pending enable reads as Turning On")
    monitor.harnessConnection?.failProxies(code: xpcConnectionInvalid)
    spin(0.2)
    check(MainActor.assumeIsolated { coordinator.menuPresentation().statusTitle } != "Status: Turning On Protection",
          "B2: once the enable fails, Turning On disappears")
    settle()
}

// B12 and B13 (B-T2): launch sends one enable. The init restore, the launch
// reconcile, and a second caller share it; a superseded action cannot
// release the transition; and the latest Off wins over the pending enable.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    HarnessInterface.flagsLine = upLine
    monitor.startMonitoring(persistUserPreference: false)
    let a = launch { await coordinator.setPersistentProtection(true) }
    let b = launch { await coordinator.setPersistentProtection(true) }
    spin()
    let connection = monitor.harnessConnection!
    check(connection.helper.commands.map(\.0) == [false], "B12: launch sends one enable, not three")
    check(MainActor.assumeIsolated { coordinator.isBusy }, "B12: the coordinator stays busy while the shared enable is in flight")
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    check(connection.helper.commands.map(\.0) == [false, true], "B12: Off during a pending enable sends a stop")
    connection.helper.commands.removeFirst().1(true)   // the enable lands late
    spin()
    connection.helper.commands.removeFirst().1(true)   // the stop confirms
    spin(until: { off.withValue { $0 } != nil && a.withValue { $0 } != nil && b.withValue { $0 } != nil }, timeout: 3)
    check(off.withValue { $0 } == true, "B12: the latest Off succeeds")
    check(!monitor.isMonitoringActive && !monitor.isMonitoringRequested, "B12: the late enable must not turn protection back on")
    check(!PingWardenPreferences.shared.isMonitoringEnabled, "B12: the saved intent ends off")
    check(MainActor.assumeIsolated { coordinator.transition } == .idle, "B12: no transition is left behind")
}

// B12: a superseded action's completion must not release a newer action's
// transition. An Off is superseded by a pause; the Off's stale reply lands
// first while the pause's stop is still in flight.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    let off = launch { await coordinator.setPersistentProtection(false) }
    spin()
    let pause = launchVoid { await coordinator.pauseForTenMinutes() }
    spin()
    check(connection.helper.commands.map(\.0) == [true, true], "B12: the Off's stop and the newer pause's stop are queued")
    connection.helper.commands.removeFirst().1(true)
    spin()
    check(off.withValue { $0 } != nil, "B12: the superseded Off completes")
    check(MainActor.assumeIsolated { coordinator.transition } == .disablingProtection,
          "B12: the superseded Off must not release the newer pause's transition")
    check(MainActor.assumeIsolated { coordinator.isBusy }, "B12: controls stay disabled while the pause's stop is in flight")
    connection.helper.commands.removeFirst().1(true)
    spin(until: { pause.withValue { $0 } }, timeout: 2)
    check(MainActor.assumeIsolated { coordinator.transition } == .idle, "B12: the owner releases its transition")
    check(MainActor.assumeIsolated { coordinator.isPauseActive }, "B12: the pause holds")
}

// B13: Game Mode ends while its session's enable is in flight. Reconcile
// must still stop the pending enable instead of treating the monitor as idle.
do {
    MainActor.assumeIsolated { resetAll() }
    let start = launchVoid { await coordinator.setGameModeActive(true) }
    spin()
    let connection = monitor.harnessConnection!
    check(connection.helper.commands.map(\.0) == [false], "B13: Game Mode sends an enable")
    let end = launchVoid { await coordinator.setGameModeActive(false) }
    spin()
    check(connection.helper.commands.map(\.0) == [false, true], "B13: ending Game Mode mid-enable sends a stop")
    connection.helper.commands.removeFirst().1(true)
    spin()
    connection.helper.commands.removeFirst().1(true)
    spin(until: { start.withValue { $0 } && end.withValue { $0 } }, timeout: 2)
    check(!monitor.isMonitoringActive && !monitor.isMonitoringRequested, "B13: the late enable must not leave protection on without an owner")
    check(MainActor.assumeIsolated { session.phase } == .idle, "B13: no session starts after Game Mode ended")
}

// B3 (B-T9): a helper restart during a Game Mode session. The bounded
// reconnect reasserts protection, the session continues, and its recap
// records the interruption.
do {
    MainActor.assumeIsolated { resetAll() }
    // A live helper answers validation within the production deadline.
    monitor.harnessDefaultReplies()
    let token = monitor.addStateObserver { Task { @MainActor in coordinator.refreshFromMonitor() } }
    defer { monitor.removeStateObserver(token) }
    let started = launchVoid { await coordinator.setGameModeActive(true) }
    spin()
    let first = monitor.harnessConnection!
    first.helper.commands.removeFirst().1(true)
    spin(until: { started.withValue { $0 } }, timeout: 2)
    check(MainActor.assumeIsolated { session.isActive }, "B3: the Game Mode session starts")
    first.helper.versions.forEach { $0("fixture-helper") }
    first.helper.versions.removeAll()
    spin()
    first.interruptionHandler?()        // launchd relaunches a crashed helper
    spin(0.2)
    check(MainActor.assumeIsolated { session.isActive }, "B3: a helper restart must not end the session")
    check(monitor.isMonitoringRequested, "B3: protection stays requested while reconnecting")
    check(MainActor.assumeIsolated { coordinator.menuPresentation().statusTitle } == "Status: Restoring Protection",
          "B3: the status says protection is being restored")
    spin(1.0)
    let replacement = monitor.harnessConnection!
    check(replacement !== first, "B3: the reconnect builds a replacement connection")
    replacement.helper.versions.removeFirst()("fixture-helper")
    spin()
    check(replacement.helper.commands.map(\.0) == [false], "B3: the replacement reasserts protection")
    replacement.helper.commands.removeFirst().1(true)
    spin()
    check(monitor.isMonitoringActive && MainActor.assumeIsolated { session.isActive },
          "B3: protection and the session both survive the restart")
    check(MainActor.assumeIsolated { session.interruptionsNoted } >= 1, "B3: the recap records the interruption")
    check(MainActor.assumeIsolated { session.endings }.isEmpty, "B3: the session did not end")
}

// B3: when the monitor gives up, the session ends as interrupted.
do {
    MainActor.assumeIsolated { resetAll() }
    let token = monitor.addStateObserver { Task { @MainActor in coordinator.refreshFromMonitor() } }
    defer { monitor.removeStateObserver(token) }
    let started = launchVoid { await coordinator.setGameModeActive(true) }
    spin()
    let first = monitor.harnessConnection!
    first.helper.commands.removeFirst().1(true)
    spin(until: { started.withValue { $0 } }, timeout: 2)
    let alerts = NSAlert.messages.count
    first.interruptionHandler?()
    spin()
    for delay in [1.05, 2.05, 4.05] {
        spin(delay)
        monitor.harnessConnection?.invalidationHandler?()
        spin()
    }
    spin(0.2)
    check(!monitor.isMonitoringRequested, "B3: exhausted retries give the request up")
    check(MainActor.assumeIsolated { session.endings }.first.map { $0.0 == .protectionFailed && $0.1 } == true,
          "B3: the session ends as interrupted once the monitor gives up")
    check(NSAlert.messages.count == alerts, "B8: reconnect exhaustion raises no alert")
    check(MainActor.assumeIsolated { coordinator.lastError }?.contains("click Repair") == true,
          "B8/B14: exhaustion is published where errors show, pointing to Repair")
}

// B3: a replacement connection that never answers counts against the retry
// cap, so a waiting session cannot hang on it forever.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    connection.interruptionHandler?()
    spin(1.1)
    check(monitor.harnessRetries == 1, "B3: the first drop uses one retry")
    spin(0.3) // the replacement's validation times out
    check(monitor.harnessRetries == 2, "B3: a silent replacement consumes the next retry")
    settle()
}

// B4 (B-T1): the app's own notification echo keeps a license message.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    LicenseManager.shared.canEnableProtection = false
    let done = launchVoid { await coordinator.handleLicenseReverification() }
    spin()
    connection.helper.commands.removeFirst().1(true)
    spin(until: { done.withValue { $0 } }, timeout: 2)
    let before = MainActor.assumeIsolated { coordinator.lastError }
    let echo = launchVoid {
        await coordinator.handleExternallyAppliedProtectionState(PingWardenPreferences.shared.effectiveMonitoringEnabled)
    }
    spin(until: { echo.withValue { $0 } }, timeout: 1)
    let after = MainActor.assumeIsolated { coordinator.lastError }
    check(before?.contains("license") == true && after == before, "B4: the echo must not clear the license message")
    check(connection.helper.states.isEmpty, "B4: the echo must not start an adoption query")
}

// B4: a real external change is still adopted, without dropping a license message.
do {
    MainActor.assumeIsolated { resetAll() }
    let connection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    let change = launchVoid { await coordinator.handleExternallyAppliedProtectionState(false) }
    spin(until: { change.withValue { $0 } }, timeout: 1)
    check(!connection.helper.states.isEmpty, "B4: a widget's change is confirmed with the helper")
    connection.helper.states.forEach { $0(true) }
    connection.helper.states.removeAll()
    spin()
    check(!monitor.isMonitoringRequested, "B4: the widget's Off is adopted")
}

// B5 (B-T6): overlapping repairs share one rebuild and one result.
do {
    MainActor.assumeIsolated { resetAll() }
    setFixtureHelperBundle(installed: true)
    defer { setFixtureHelperBundle(installed: false) }
    SMAppService.fixtureAllowsRegistration = true
    let results = LockedValue<[String]>([])
    monitor.repairHelperRegistration(presentsErrors: false) { ok in results.withValue { $0.append("first=\(ok)") } }
    spin(0.05)
    check(monitor.isRepairingHelper && MainActor.assumeIsolated { coordinator.isRepairingHelper },
          "B5: repair in progress is exposed to the UI")
    monitor.repairHelperRegistration(presentsErrors: false) { ok in results.withValue { $0.append("second=\(ok)") } }
    spin(until: { SMAppService.registerCalls >= 1 }, timeout: 4)
    FakeHelper.autoReplyVersion = "fixture-helper"
    spin(until: { results.withValue { $0 }.count == 2 }, timeout: 5)
    check(results.withValue { $0 }.sorted() == ["first=true", "second=true"], "B5: both callers get the shared result")
    check(SMAppService.unregisterCalls == 1 && SMAppService.registerCalls == 1, "B5: overlapping repairs rebuild once")
    check(!monitor.isRepairingHelper, "B5: repair in progress clears when it ends")
}

// B6 (B-T7): a repair that tears down a confirmed helper raises no
// lost-connection error, resets the retry count, and restores protection.
do {
    MainActor.assumeIsolated { resetAll() }
    setFixtureHelperBundle(installed: true)
    defer { setFixtureHelperBundle(installed: false) }
    let confirmedConnection = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    SMAppService.fixtureAllowsRegistration = true
    SMAppService.statusAfterRegister = .requiresApproval
    NSXPCConnection.invalidateWhenUnregistered = true
    SMAppService.onUnregister = { DispatchQueue.main.async { confirmedConnection.interruptionHandler?() } }
    let alerts = NSAlert.messages.count
    let result = LockedValue<Bool?>(nil)
    monitor.repairHelperRegistration(presentsErrors: false) { ok in result.withValue { $0 = ok } }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        SMAppService.fixtureStatus = .enabled
        FakeHelper.autoReplyVersion = "fixture-helper"
    }
    spin(until: { result.withValue { $0 } != nil }, timeout: 8)
    spin(0.1)
    check(result.withValue { $0 } == true, "B6: the repair succeeds")
    check(NSAlert.messages.count == alerts, "B6: no alert fires during the repair")
    check(automatedErrors.filter { $0.contains("Lost connection") }.isEmpty, "B6: no lost-connection error during the repair")
    check(monitor.harnessRetries == 0, "B6: a successful repair resets the retry count")
    let reasserts = monitor.harnessConnection?.helper.commands.map(\.0) ?? []
    check(reasserts == [false], "B6: the repaired helper is asked to restore protection")
    settle()
    check(monitor.isMonitoringActive, "B6: protection is restored after the repair")
}

// B7 (B-T10): launch never enables protection for an unapproved helper.
do {
    let action = ProtectionExperiencePolicy.launchIntentAction(
        persistentProtectionEnabled: true,
        licenseAllowsProtection: true,
        helperRegistered: false
    )
    check(action == .waitForSetup, "B7: a saved intent waits for Finish Setup when the helper is not approved")
    MainActor.assumeIsolated { resetAll() }
    SMAppService.fixtureStatus = .requiresApproval
    PingWardenPreferences.shared.isMonitoringEnabled = true
    MainActor.assumeIsolated { coordinator.noteSetupIncomplete() }
    spin(0.2)
    check(SMAppService.openSettingsCalls == 0, "B7: launch must not open Login Items")
    check(MainActor.assumeIsolated { coordinator.menuPresentation().protectionTitle } == "Finish Setup...",
          "B7: the menu offers Finish Setup")
    check(MainActor.assumeIsolated { coordinator.lastError } == ProtectionFailureCopy.setupIncomplete,
          "B7: the reason protection is off is shown")
}

// B8: Game Mode failures never raise alerts, and the error is published once.
do {
    MainActor.assumeIsolated { resetAll() }
    let alerts = NSAlert.messages.count
    let start = launchVoid { await coordinator.setGameModeActive(true) }
    spin()
    monitor.harnessConnection?.helper.commands.removeFirst().1(false)   // helper refuses
    spin(until: { start.withValue { $0 } }, timeout: 2)
    check(NSAlert.messages.count == alerts, "B8: a failed Game Mode enable raises no alert")
    check(MainActor.assumeIsolated { coordinator.lastError }?.contains("latency session did not start") == true,
          "B8: the Game Mode failure is published to the coordinator")
}

// B8: a setup failure reported to a caller with its own surface stacks no alert.
do {
    MainActor.assumeIsolated { resetAll() }
    setFixtureHelperBundle(installed: false)
    SMAppService.fixtureStatus = .notRegistered
    let alerts = NSAlert.messages.count
    let result = LockedValue<Bool?>(nil)
    monitor.registerHelper(presentsErrors: false) { ok in result.withValue { $0 = ok } }
    spin()
    check(result.withValue { $0 } == false, "B8: a missing helper bundle fails registration")
    check(NSAlert.messages.count == alerts, "B8: presentsErrors false raises no alert")
    check(monitor.lastSetupFailureMessage?.contains("reinstall") == true, "B8: the specific failure is kept for the caller")
}

// B9: a saved intent is retried once the silent helper answers again, and
// the not-responding message clears on its reply.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    MainActor.assumeIsolated { coordinator.noteHelperNotResponding() }
    check(MainActor.assumeIsolated { coordinator.lastError } == ProtectionFailureCopy.helperNotResponding,
          "B9: setup shows the not-responding message")
    let probe = LockedValue<Bool?>(nil)
    monitor.confirmHelperResponds(attempts: 1) { ok in probe.withValue { $0 = ok } }
    spin()
    let connection = monitor.harnessConnection!
    connection.helper.versions.removeFirst()("fixture-helper")
    spin(0.2)
    check(probe.withValue { $0 } == true, "B9: the probe sees the helper answer")
    check(MainActor.assumeIsolated { coordinator.lastError } == nil, "B9: a helper reply clears the not-responding message")
    check(connection.helper.commands.map(\.0) == [false], "B9: the saved intent is retried once the helper answers")
    settle()
    check(monitor.isMonitoringActive, "B9: the retried intent turns protection on")
}

// B9: a helper that answers but declines does not start a retry loop.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    let enable = launch { await coordinator.setPersistentProtection(true) }
    spin()
    monitor.harnessConnection?.helper.commands.removeFirst().1(false)
    spin(until: { enable.withValue { $0 } != nil }, timeout: 2)
    spin(0.2)
    check(monitor.harnessConnection?.helper.commands.isEmpty == true, "B9: a declining helper is not retried automatically")
}

// B11 (B-T8): quitting during a pending first enable sends a stop, and quit
// waits for the helper's reply.
do {
    MainActor.assumeIsolated { resetAll() }
    let pending = launch { await coordinator.setPersistentProtection(true) }
    spin()
    let connection = monitor.harnessConnection!
    let quit = LockedValue(false)
    let waiting = MainActor.assumeIsolated {
        coordinator.prepareForTermination { quit.withValue { $0 = true } }
    }
    check(waiting, "B11: quit waits while an enable is pending")
    check(connection.helper.commands.map(\.0) == [false, true], "B11: quit sends a stop behind the pending enable")
    spin(0.1)
    check(!quit.withValue { $0 }, "B11: quit waits for the stop's reply")
    connection.helper.commands.removeFirst().1(true)
    connection.helper.commands.removeFirst().1(true)
    spin(0.1)
    check(quit.withValue { $0 }, "B11: the stop's reply lets quit proceed")
    spin(until: { pending.withValue { $0 } != nil }, timeout: 2)
    check(!monitor.isMonitoringActive, "B11: the late enable does not outlive quit")
    let later = launch { await coordinator.setPersistentProtection(true) }
    spin(until: { later.withValue { $0 } != nil }, timeout: 1)
    check(later.withValue { $0 } == false && monitor.harnessConnection?.helper.commands.isEmpty == true,
          "B11: no new enable starts while quitting")
}

// B11: a silent helper cannot hold quit for more than about 1.5 seconds.
do {
    MainActor.assumeIsolated { resetAll() }
    _ = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    let quit = LockedValue(false)
    let started = Date()
    let waiting = MainActor.assumeIsolated {
        coordinator.prepareForTermination { quit.withValue { $0 = true } }
    }
    check(waiting, "B11: quit waits while protection is on")
    spin(until: { quit.withValue { $0 } }, timeout: 3)
    let elapsed = Date().timeIntervalSince(started)
    check(quit.withValue { $0 } && elapsed >= 1.4 && elapsed < 2.5, "B11: quit proceeds after about 1.5 seconds without a reply")
    let nothingHeld = MainActor.assumeIsolated {
        coordinator.harnessReset()
        monitor.harnessReset()
        return coordinator.prepareForTermination { }
    }
    check(!nothingHeld, "B11: quit does not wait when nothing is held")
    settle()
}

// B16: wake settles a pause that expired while the Mac slept.
do {
    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    MainActor.assumeIsolated { coordinator.harnessSetPause(until: Date().addingTimeInterval(-5)) }
    let wake = launchVoid { await coordinator.handleSystemWake() }
    spin()
    check(monitor.harnessConnection?.helper.commands.map(\.0) == [false], "B16: an expired pause resumes protection on wake")
    settle()
    spin(until: { wake.withValue { $0 } }, timeout: 2)
    check(MainActor.assumeIsolated { coordinator.pauseUntil } == nil, "B16: the expired pause is cleared")

    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    MainActor.assumeIsolated { coordinator.harnessSetPause(until: Date().addingTimeInterval(300)) }
    let wakeDuringPause = launchVoid { await coordinator.handleSystemWake() }
    spin(until: { wakeDuringPause.withValue { $0 } }, timeout: 1)
    check((monitor.harnessConnection?.helper.commands ?? []).isEmpty, "B16: an active pause stays paused on wake")

    MainActor.assumeIsolated { resetAll() }
    PingWardenPreferences.shared.isMonitoringEnabled = true
    let wakeWithIntent = launchVoid { await coordinator.handleSystemWake() }
    spin()
    check(monitor.harnessConnection?.helper.commands.map(\.0) == [false], "B16: wake reconciles a saved intent")
    settle()
    spin(until: { wakeWithIntent.withValue { $0 } }, timeout: 2)
}

// Cross-lane: the helper test reports a rejected connection at once.
do {
    MainActor.assumeIsolated { resetAll() }
    FakeHelper.answersStatus = false
    let result = LockedValue<(Bool, String)?>(nil)
    let started = Date()
    _ = monitor.harnessConnection
    DispatchQueue.global().async {
        let check = monitor.performHealthCheck()
        result.withValue { $0 = (check.isHealthy, check.message) }
    }
    spin(0.1)
    monitor.harnessConnection?.failProxies(code: xpcConnectionInvalid)
    spin(until: { result.withValue { $0 } != nil }, timeout: 5)
    let outcome = result.withValue { $0 }
    check(outcome?.0 == false, "Cross-lane: a rejected helper fails the test")
    check(outcome?.1.contains("rejected the connection") == true, "Cross-lane: the test says the helper rejected the connection")
    check(Date().timeIntervalSince(started) < 1.5, "Cross-lane: a rejection does not wait out both timeouts")
}

// Cross-lane: the helper test does not call a missing awdl0 "still up".
do {
    MainActor.assumeIsolated { resetAll() }
    _ = MainActor.assumeIsolated { turnOnThroughCoordinator() }
    FakeHelper.autoReplyVersion = "fixture-helper"
    HarnessInterface.flagsLine = "ifconfig: interface awdl0 does not exist"
    let result = LockedValue<(Bool, String)?>(nil)
    DispatchQueue.global().async {
        let check = monitor.performHealthCheck()
        result.withValue { $0 = (check.isHealthy, check.message) }
    }
    spin(until: { result.withValue { $0 } != nil }, timeout: 5)
    check(result.withValue { $0 }?.0 == true, "B14: a Mac without awdl0 passes the helper test")
    check(result.withValue { $0 }?.1.contains("still up") == false, "B14: a missing awdl0 is not reported as still up")
}

// Cross-lane: the launch probe finishes at once when the helper rejects it.
do {
    MainActor.assumeIsolated { resetAll() }
    monitor.harnessDefaultReplies()
    let result = LockedValue<Bool?>(nil)
    let started = Date()
    monitor.confirmHelperResponds(attempts: 1) { ok in result.withValue { $0 = ok } }
    spin()
    monitor.harnessConnection?.failProxies(code: xpcConnectionInvalid)
    spin(until: { result.withValue { $0 } != nil }, timeout: 3)
    check(result.withValue { $0 } == false, "Cross-lane: a rejected probe reports the helper silent")
    check(Date().timeIntervalSince(started) < 1, "Cross-lane: a rejected probe does not wait out the two-second timeout")
    check(monitor.lastConnectionFailure == .rejected(code: xpcConnectionInvalid), "Cross-lane: the rejection is kept for messages")
    monitor.harnessFastReplies()
}

MainActor.assumeIsolated { resetAll() }
print("Coordinator checks complete. Checks: \(checks). Failures: \(failures.count)")
exit(failures.isEmpty ? 0 : 1)
