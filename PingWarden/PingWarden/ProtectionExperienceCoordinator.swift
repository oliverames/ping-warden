import Foundation
import os.log

private let protectionExperienceLog = Logger(
    subsystem: "com.amesvt.pingwarden",
    category: "ProtectionExperience"
)

@MainActor
final class ProtectionExperienceCoordinator: ObservableObject {
    static let shared = ProtectionExperienceCoordinator()

    enum Transition: Equatable {
        case idle
        case enablingProtection
        case disablingProtection
    }

    @Published private(set) var pauseUntil: Date?
    @Published private(set) var transition: Transition = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var gameModeActive = false

    private let monitor = PingWardenMonitor.shared
    private let preferences = PingWardenPreferences.shared
    private let session = ProtectedSessionCoordinator.shared
    private let license = LicenseManager.shared
    private var pauseTimer: Timer?
    private var actionGeneration = 0
    /// The action that set `transition`. Only that action may release it, so
    /// a superseded action finishing late cannot clear a newer one's
    /// "Turning On" and re-enable controls while its command is in flight.
    private var transitionOwner = 0
    private var gameModeGeneration = 0
    private var requestedSessionTrigger: ProtectedSessionTrigger?
    /// Set once the helper goes unanswered; cleared by its next reply.
    private var helperSilent = false
    /// The error currently shown because the helper was silent, so a reply
    /// from the helper clears that message and nothing more specific.
    private var silenceMessage: String?
    private var lastAutomaticRetry: Date?
    private(set) var isTerminating = false
    /// Set by `finishForTermination` (from `applicationWillTerminate`), the
    /// point after which the process really exits. Until then a quit that
    /// `prepareForTermination` began can still be abandoned by macOS.
    private var terminationCommitted = false
    /// Identifies the latest `prepareForTermination`, so only its own
    /// cancellation check can clear `isTerminating`.
    private var terminationAttempt = 0
    /// How long after quit was answered `applicationWillTerminate` may take
    /// before the quit is treated as cancelled. AppKit calls it immediately
    /// after a .terminateNow or a positive reply, so this is generous.
    var terminationCancelGrace: TimeInterval = 10
    /// All repair entry points share one operation, including the final
    /// reconciliation. A second caller waits for the same result.
    private var helperRepairTask: Task<HelperTestReport, Never>?
    /// Asks Control Center to re-query the Ping Protection control after a
    /// recovery point (#101). The app installs a coalescing handler; nil
    /// leaves the control alone.
    var controlRefreshHandler: ((ControlCenterRefreshTrigger) -> Void)?
    /// Offers Repair when the helper is not working while protection needs
    /// it. Returns false when the offer cannot be shown right now (a game
    /// is in front, the setup window is open); it stays due, and
    /// `retryPendingRepairOffer()` asks again. Nil offers nothing.
    var repairOfferHandler: ((HelperRepairOffer.Problem) -> Bool)?
    /// How long a helper problem lasts before Repair is offered.
    var repairOfferDebounce: TimeInterval = HelperRepairOffer.debounce
    private var repairOfferTracker = HelperRepairOffer.Tracker()
    private var repairOfferCheck: Task<Void, Never>?

    private init() {
        restorePersistedPauseIfActive()
        monitor.automatedErrorHandler = { [weak self] message in
            Task { @MainActor in
                self?.publishAutomatedError(message)
            }
        }
        monitor.helperResponseHandler = { [weak self] in
            Task { @MainActor in
                self?.helperDidRespond()
            }
        }
    }

    var isBusy: Bool {
        transition != .idle || session.isTransitioning
    }

    /// Whether a repair is checking registration or restoring protection.
    /// Views that offer Repair or Finish Setup disable those controls meanwhile.
    var isRepairingHelper: Bool {
        helperRepairTask != nil || monitor.isRepairingHelper
    }

    /// Unknown at launch is not a failure. Offer repair only after an
    /// unanswered request, and keep the action visible while it completes.
    var shouldOfferHelperRepair: Bool {
        isRepairingHelper || (monitor.isHelperRegistered && helperSilent)
    }

    var canRepairHelper: Bool {
        !isTerminating && !isBusy && !isRepairingHelper && !monitor.isHelperSetupInProgress
    }

    /// Called only after an explicit Repair confirmation. Reconcile current
    /// policy instead of replaying a snapshot of the saved preference: a
    /// pause, session, license change or newer Off must still win.
    /// Checks the helper and rebuilds its registration in one go. The
    /// Repair surfaces use `checkHelperForRepair` and `reapproveHelper`
    /// instead, so macOS announces nothing before the person is told why.
    func repairHelperConnection() async -> HelperTestReport {
        await performHelperRepair { monitor, done in
            monitor.repairHelperRegistration(presentsErrors: false, completion: done)
        }
    }

    /// What Repair's check found.
    enum RepairCheck: Equatable {
        /// The helper answered and current protection policy was
        /// reconciled. The report says so, or explains what was not restored.
        case finished(HelperTestReport)
        /// The helper must be registered again, which needs the person's
        /// approval in System Settings. Nothing has changed yet.
        case needsApproval(HelperProbeOutcome)
    }

    /// Repair's first step. Asks whether the helper answers without
    /// touching its registration. An answering helper finishes Repair here,
    /// with the same reconciliation as a full repair.
    func checkHelperForRepair() async -> RepairCheck {
        let outcome = ProbeOutcomeBox()
        let report = await performHelperRepair { monitor, done in
            monitor.probeHelper { result in
                outcome.value = result
                done(result == .responding)
            }
        }
        if let result = outcome.value, result.needsReregistration,
           report.title == RepairResultCopy.failureTitle {
            return .needsApproval(result)
        }
        return .finished(report)
    }

    /// Repair's second step, started from the Approve Helper button:
    /// register the helper again, wait for approval and a reply, then
    /// reconcile current protection policy.
    func reapproveHelper() async -> HelperTestReport {
        await performHelperRepair { monitor, done in
            monitor.reregisterHelper(presentsErrors: false, completion: done)
        }
    }

    /// Carries the probe's outcome out of the monitor's callback.
    private final class ProbeOutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: HelperProbeOutcome?
        var value: HelperProbeOutcome? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    /// The shared repair operation: one at a time, reassertion held back
    /// while the monitor works, then reconciliation of current policy.
    private func performHelperRepair(
        _ step: @escaping @MainActor (PingWardenMonitor, @escaping @Sendable (Bool) -> Void) -> Void
    ) async -> HelperTestReport {
        if let helperRepairTask { return await helperRepairTask.value }
        guard canRepairHelper else {
            return HelperTestReport(
                title: "Helper Repair Could Not Start",
                message: "Wait for the current protection change to finish, then try Repair again."
            )
        }
        let repairGeneration = actionGeneration
        let task = Task { @MainActor in
            monitor.defersProtectionReassertion = true
            defer { monitor.defersProtectionReassertion = false }
            let repaired = await withCheckedContinuation { continuation in
                step(monitor) {
                    continuation.resume(returning: $0)
                }
            }
            guard !isTerminating else {
                return HelperTestReport(title: "Helper Repair Stopped", message: "Ping Warden is quitting. Repair did not finish.")
            }
            guard repaired else {
                return HelperTestReport(
                    title: RepairResultCopy.failureTitle,
                    message: monitor.lastSetupFailureMessage ?? RepairResultCopy.failureMessage
                )
            }
            // A newer On/Off, pause or license change owns its command even
            // before its reply updates the saved preference. Replaying that
            // old preference here would supersede the newer operation.
            if actionGeneration == repairGeneration,
               transition == .idle, !monitor.isProtectionCommandInFlight {
                await reconcileProtection()
            }
            guard !isTerminating else {
                return HelperTestReport(title: "Helper Repair Stopped", message: "Ping Warden is quitting. Repair did not finish.")
            }
            if transition != .idle || monitor.isProtectionCommandInFlight {
                return HelperTestReport(
                    title: "Protection Change In Progress",
                    message: "The helper answered. Ping Warden is still applying your current protection change. Check its status when that change finishes."
                )
            }
            let expected = ProtectionExperiencePolicy.shouldEnableProtection(for: policyState, now: Date())
            guard !helperSilent, expected == monitor.isMonitoringActive else {
                return HelperTestReport(
                    title: "Protection Could Not Be Restored",
                    message: lastError ?? RepairResultCopy.restoringFailureMessage
                )
            }
            return HelperTestReport(
                title: RepairResultCopy.successTitle,
                message: RepairResultCopy.successMessage(protectionOn: monitor.isMonitoringActive)
            )
        }
        helperRepairTask = task
        objectWillChange.send()
        let result = await task.value
        helperRepairTask = nil
        // The person chose Repair and has its result: a helper still not
        // working is not offered Repair again on its own this episode.
        let stillFailing = result.title == RepairResultCopy.failureTitle && monitor.isHelperRegistered
        repairOfferTracker.markOffered(
            problem: currentHelperProblem ?? (stillFailing ? .notResponding : nil),
            now: Date()
        )
        objectWillChange.send()
        // Whatever the outcome, the helper was rebuilt or torn down, so the
        // control's last rendering may no longer match awdl0.
        if !isTerminating {
            controlRefreshHandler?(.repairFinished)
        }
        return result
    }

    /// Whether a pause is in effect right now. A persisted pause restored at
    /// launch outranks the stored protection intent until it expires.
    var isPauseActive: Bool {
        pauseUntil.map { $0 > Date() } ?? false
    }

    var policyState: ProtectionExperiencePolicy.State {
        ProtectionExperiencePolicy.State(
            helperAvailable: monitor.isHelperRegistered,
            persistentProtectionEnabled: preferences.isMonitoringEnabled,
            effectiveProtectionEnabled: monitor.isMonitoringActive,
            sessionPhase: session.phase,
            sessionTrigger: session.activeTrigger,
            pauseUntil: pauseUntil,
            licenseAllowsProtection: license.canEnableProtection,
            protectionRequested: monitor.isMonitoringRequested,
            commandInFlight: transition != .idle || monitor.isProtectionCommandInFlight,
            helperResponding: !helperSilent
        )
    }

    /// What the protection toggle does right now, shared by the menu item
    /// and the Dashboard button so their titles and actions agree.
    func toggleAction(now: Date = Date()) -> ProtectionExperiencePolicy.ToggleAction {
        ProtectionExperiencePolicy.toggleAction(for: policyState, now: now)
    }

    func menuPresentation(now: Date = Date()) -> ProtectionExperiencePolicy.MenuPresentation {
        let base = ProtectionExperiencePolicy.presentation(for: policyState, now: now)
        switch transition {
        case .idle:
            return base
        case .enablingProtection:
            return ProtectionExperiencePolicy.MenuPresentation(
                protectionTitle: "Turning On Ping Protection…",
                protectionActionEnabled: false,
                pauseTitle: nil,
                pauseActionEnabled: false,
                statusTitle: "Status: Turning On Protection"
            )
        case .disablingProtection:
            return ProtectionExperiencePolicy.MenuPresentation(
                protectionTitle: "Turning Off Ping Protection…",
                protectionActionEnabled: false,
                pauseTitle: nil,
                pauseActionEnabled: false,
                statusTitle: "Status: Turning Off Protection"
            )
        }
    }

    func refreshFromMonitor() {
        objectWillChange.send()

        guard transition == .idle,
              session.isActive,
              !monitor.isMonitoringActive else {
            return
        }

        if monitor.isMonitoringRequested {
            // A helper restart drops confirmation while the monitor's
            // bounded reconnect reapplies the same request. The game is
            // still running, so the session continues and its recap
            // records the gap. The session ends only if the monitor gives up.
            session.noteProtectionInterrupted()
            return
        }

        Task {
            await endSession(
                reason: .protectionFailed,
                protectionWasInterrupted: true
            )
        }
    }

    /// Called after a license re-verification settles. A revoked or
    /// invalid license while protection is actively enabled turns
    /// protection off immediately; the user sees why in the menu and
    /// Settings. An unreachable API never triggers this: the offline
    /// grace window in LicensePolicy covers that case.
    func handleLicenseReverification() async {
        objectWillChange.send()

        if license.canEnableProtection {
            if lastError?.localizedCaseInsensitiveContains("license") == true {
                lastError = nil
            }
            return
        }

        // Also cancel an enable whose helper reply has not arrived yet.
        guard monitor.isMonitoringActive
                || monitor.isMonitoringRequested
                || monitor.isProtectionDesired
                || preferences.isMonitoringEnabled
                || isBusy else { return }

        actionGeneration += 1
        let generation = actionGeneration
        clearPause()
        if session.phase != .idle {
            requestedSessionTrigger = nil
            await session.stop(
                endReason: .protectionTurnedOff,
                protectionWasInterrupted: true
            )
        }
        guard generation == actionGeneration, !license.canEnableProtection else { return }
        beginTransition(.disablingProtection, for: generation)
        let success = await monitor.setProtectionEnabled(
            false,
            persistUserPreference: true
        )
        endTransition(for: generation)
        guard generation == actionGeneration else { return }
        guard !license.canEnableProtection else {
            lastError = nil
            objectWillChange.send()
            return
        }
        lastError = success
            ? LicenseCopy.revoked
            : "The license for Ping Protection is no longer valid, and it could not turn off cleanly. Quit Ping Warden to restore wireless sharing."
        objectWillChange.send()
    }

    /// Called at launch when the persisted protection intent survived
    /// but the entitlement did not (transition ended, refund, forged
    /// preference). The monitor already refused to restore AWDL-down;
    /// this clears the stale intent so the menu does not claim
    /// protection is on, and tells the user why.
    func noteLaunchLicenseGate() {
        preferences.isMonitoringEnabled = false
        lastError = LicenseCopy.stayedOffAtLaunch(transitionEnded: license.grandfatherWindowExpired)
        objectWillChange.send()
    }

    /// The helper is registered but did not answer at launch. Point to the
    /// repair path without replacing a more specific message.
    func noteHelperNotResponding() {
        helperSilent = true
        defer { evaluateRepairOffer() }
        guard lastError == nil else {
            objectWillChange.send()
            return
        }
        showSilenceError(ProtectionFailureCopy.helperNotResponding)
    }

    /// Launch found a saved intent to protect but no approved helper. The
    /// menu already offers Finish Setup; this says why protection is off
    /// without opening Login Items for a person who did not ask.
    func noteSetupIncomplete() {
        defer { evaluateRepairOffer() }
        guard lastError == nil else { return }
        lastError = ProtectionFailureCopy.setupIncomplete
        objectWillChange.send()
    }

    // MARK: Repair offers

    /// The helper's problem as a Repair offer sees it: registered but
    /// silent, or not approved while protection is saved as on.
    private var currentHelperProblem: HelperRepairOffer.Problem? {
        if monitor.isHelperRegistered {
            return helperSilent ? .notResponding : nil
        }
        return preferences.isMonitoringEnabled ? .notApproved : nil
    }

    /// Protection is on, wanted, being turned on, paused (it resumes), or
    /// held by a session or Game Mode.
    private var protectionNeedsHelper: Bool {
        preferences.isMonitoringEnabled
            || monitor.isMonitoringActive
            || monitor.isMonitoringRequested
            || monitor.isProtectionDesired
            || transition == .enablingProtection
            || session.phase != .idle
            || requestedSessionTrigger != nil
            || gameModeActive
            || pauseUntil != nil
    }

    /// Decide whether to offer Repair now, later, or not at all, using
    /// `HelperRepairOffer` in Core: once per failure episode, after the
    /// debounce, only while protection needs the helper and a license
    /// allows it. Offering never repairs anything by itself.
    func evaluateRepairOffer() {
        repairOfferCheck?.cancel()
        repairOfferCheck = nil
        let state = HelperRepairOffer.State(
            problem: currentHelperProblem,
            licenseAllowsProtection: license.canEnableProtection,
            protectionNeeded: protectionNeedsHelper,
            busy: isTerminating || isBusy || isRepairingHelper || monitor.isHelperSetupInProgress
        )
        switch repairOfferTracker.evaluate(state, now: Date(), debounce: repairOfferDebounce) {
        case .none:
            return
        case .wait(let delay):
            let nanoseconds = UInt64(max(0.05, delay) * 1_000_000_000)
            repairOfferCheck = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.evaluateRepairOffer()
            }
        case .offer(let problem):
            guard let repairOfferHandler else { return }
            protectionExperienceLog.info("Offering Repair: helper \(problem.rawValue, privacy: .public)")
            if repairOfferHandler(problem) {
                repairOfferTracker.markOffered(problem: problem, now: Date())
            }
        }
    }

    /// After wake, ask a helper that protection needs whether it answers,
    /// without touching its registration. Wake itself sends a command only
    /// when protection must change, so a helper that died during sleep
    /// would otherwise go unnoticed. A helper already known silent, or one
    /// being repaired, is not asked again. The app calls this a few
    /// seconds after wake so the helper has time to come back.
    func confirmHelperAfterWake() {
        guard !isTerminating, license.canEnableProtection, protectionNeedsHelper,
              monitor.isHelperRegistered, !helperSilent, !isRepairingHelper else { return }
        monitor.confirmHelperResponds { [weak self] responds in
            Task { @MainActor in
                guard let self, !responds, !self.isTerminating else { return }
                protectionExperienceLog.warning("Helper did not answer after wake")
                self.noteHelperNotResponding()
            }
        }
    }

    /// An offer that could not be shown earlier (a game in front, the setup
    /// window open) is asked for again, for example when Ping Warden
    /// becomes active or Game Mode ends.
    func retryPendingRepairOffer() {
        evaluateRepairOffer()
    }

    /// Repair was offered by another surface (the toggle's failure alert)
    /// or started by the person: no automatic offer this episode.
    func noteRepairOffered() {
        repairOfferCheck?.cancel()
        repairOfferCheck = nil
        repairOfferTracker.markOffered(problem: currentHelperProblem, now: Date())
    }

    @discardableResult
    func setPersistentProtection(_ enabled: Bool) async -> Bool {
        // The license gate covers every path that would put AWDL down:
        // persistent toggles, latency sessions, Game Mode, and launch
        // reconciliation all funnel through the two entry points below.
        if enabled, !license.canEnableProtection {
            lastError = LicenseCopy.required(transitionEnded: license.grandfatherWindowExpired)
            objectWillChange.send()
            return false
        }
        guard !enabled || !isTerminating else { return false }

        actionGeneration += 1
        let generation = actionGeneration
        lastError = nil
        silenceMessage = nil
        clearPause()

        if !enabled, session.phase != .idle {
            requestedSessionTrigger = nil
            await session.stop(
                endReason: .protectionTurnedOff,
                protectionWasInterrupted: false
            )
            guard generation == actionGeneration else { return false }
        }

        if enabled, monitor.isMonitoringActive {
            preferences.isMonitoringEnabled = true
            objectWillChange.send()
            return true
        }

        // Off always reaches the helper: the stop is idempotent, and only
        // the helper knows whether it is still enforcing. Earlier readings
        // of the interface or of lastKnownState cannot stand in for it.
        let wasRequested = monitor.isMonitoringRequested
        let wasActive = monitor.isMonitoringActive
        let enablePending = monitor.isProtectionDesired

        beginTransition(enabled ? .enablingProtection : .disablingProtection, for: generation)
        var success = await monitor.setProtectionEnabled(
            enabled,
            persistUserPreference: true
        )
        guard generation == actionGeneration else {
            // A newer action or an externally applied state owns the outcome.
            endTransition(for: generation)
            objectWillChange.send()
            return success
        }

        let failure = success ? nil : monitor.lastCommandFailure
        if !success, !enabled, failure?.helperDidNotAnswer == true {
            // A silent helper cannot confirm the stop. When this app never
            // asked for protection and awdl0 is up, nothing is being
            // blocked, so Off succeeds quietly instead of warning that
            // wireless sharing may be unavailable.
            let interfaceUp = await monitor.awdlInterfaceIsUp()
            guard generation == actionGeneration else {
                endTransition(for: generation)
                objectWillChange.send()
                return false
            }
            if HelperRecovery.offSatisfiedWithoutHelper(
                wasRequested: wasRequested,
                wasActive: wasActive,
                enablePending: enablePending,
                interfaceUp: interfaceUp
            ) {
                preferences.isMonitoringEnabled = false
                preferences.effectiveMonitoringEnabled = false
                preferences.lastKnownState = "up"
                success = true
            }
        }

        endTransition(for: generation)
        if !success {
            reportCommandFailure(enabled ? .turnOn : .turnOff, failure: failure)
        } else if failure?.helperDidNotAnswer == true {
            helperSilent = true
        }
        objectWillChange.send()
        return success
    }

    /// Turn protection on after the person explicitly activated a license,
    /// through the same path as their own toggle. Only the license
    /// activation surfaces call this, never launch-time or periodic
    /// re-verification. A pause, a session, or a change already in flight
    /// is left alone; `LicenseActivationProtection` says why.
    @discardableResult
    func turnOnProtectionAfterLicenseActivation() async -> LicenseActivationProtection {
        let decision = LicenseActivationProtection.decide(LicenseActivationProtection.State(
            canEnableProtection: license.canEnableProtection,
            protectionOn: monitor.isMonitoringActive,
            savedChoiceOn: preferences.isMonitoringEnabled,
            pauseActive: isPauseActive,
            sessionActive: session.phase != .idle,
            changeInFlight: isTerminating || isBusy || isRepairingHelper
                || monitor.isProtectionCommandInFlight
        ))
        protectionExperienceLog.info(
            "License activated; protection follow-up: \(String(describing: decision), privacy: .public)"
        )
        guard decision == .turnOn else { return decision }
        await setPersistentProtection(true)
        return decision
    }

    @discardableResult
    func startManualSession() async -> Bool {
        await startSession(trigger: .manual, gameModeRequest: nil)
    }

    func endManualSession() async {
        await endSession(reason: .endedByUser, protectionWasInterrupted: false)
    }

    func pauseForTenMinutes() async {
        guard monitor.isHelperRegistered else { return }
        actionGeneration += 1
        let generation = actionGeneration
        lastError = nil
        silenceMessage = nil

        if session.phase != .idle {
            requestedSessionTrigger = nil
            await session.stop(
                endReason: .protectionPaused,
                protectionWasInterrupted: false
            )
            guard generation == actionGeneration else { return }
        }

        pauseUntil = Date().addingTimeInterval(10 * 60)
        preferences.protectionPauseUntil = pauseUntil
        schedulePauseTimer()
        beginTransition(.disablingProtection, for: generation)
        let success = await monitor.setProtectionEnabled(
            false,
            persistUserPreference: false
        )
        endTransition(for: generation)
        if generation != actionGeneration {
            // Superseded while the disable was in flight, for example by a
            // widget-driven state change. The winner owns both the radio and
            // the UI; stay quiet instead of reporting a failure the user
            // did not cause.
            objectWillChange.send()
            return
        }
        if !success {
            clearPause()
            reportCommandFailure(.pause, failure: monitor.lastCommandFailure)
        }
        objectWillChange.send()
    }

    func resumeProtection() async {
        clearPause()
        lastError = nil
        silenceMessage = nil

        if gameModeActive, session.phase == .idle {
            _ = await startSession(
                trigger: .gameMode,
                gameModeRequest: gameModeGeneration
            )
            return
        }

        await reconcileProtection()
    }

    func setGameModeActive(_ active: Bool) async {
        gameModeGeneration += 1
        let request = gameModeGeneration
        gameModeActive = active

        if active {
            guard !ProtectionExperiencePolicy.isPaused(policyState, now: Date()),
                  session.phase == .idle else {
                return
            }
            _ = await startSession(trigger: .gameMode, gameModeRequest: request)
            return
        }

        if session.activeTrigger == .gameMode
            || (session.phase == .starting && requestedSessionTrigger == .gameMode) {
            await endSession(reason: .gameModeEnded, protectionWasInterrupted: false)
        } else {
            await reconcileProtection()
        }
    }

    func handleExternallyAppliedProtectionState(_ enabled: Bool) async {
        // A user toggle's XPC reply writes the shared preference, which loops
        // back here through the distributed notification. A signal that
        // agrees with the in-flight transition is that action's own echo:
        // bumping the generation would stale the awaiting action and strand
        // `transition` non-idle, disabling every protection control.
        if isEchoOfInFlightTransition(enabled) { return }
        // Every preference write this app makes posts the same notification
        // and arrives here after the write that caused it. When the shared
        // state already matches what this app requested, nothing external
        // happened; adopting it would clear a license message, cancel a
        // pause, and supersede the actions that just finished.
        if enabled == monitor.isMonitoringRequested {
            objectWillChange.send()
            return
        }
        actionGeneration += 1
        // A license message explains why protection is off; a widget toggle
        // does not make it untrue.
        if lastError?.localizedCaseInsensitiveContains("license") != true {
            lastError = nil
        }
        clearPause()
        // The external writer owns the radio now; release any transition a
        // superseded local action left behind so the UI stays interactive.
        transition = .idle
        transitionOwner = actionGeneration
        monitor.adoptExternallyAppliedMonitoringState(enabled)

        if !enabled, session.phase != .idle {
            requestedSessionTrigger = nil
            await session.stop(
                endReason: .protectionTurnedOff,
                protectionWasInterrupted: true
            )
        }

        objectWillChange.send()
    }

    private func isEchoOfInFlightTransition(_ enabled: Bool) -> Bool {
        switch transition {
        case .idle:
            return false
        case .enablingProtection:
            return enabled
        case .disablingProtection:
            return !enabled
        }
    }

    /// Whether protection might be held by the helper, including a first
    /// enable whose reply has not arrived.
    private var protectionMayBeHeld: Bool {
        monitor.isMonitoringRequested
            || monitor.isMonitoringActive
            || monitor.isProtectionDesired
    }

    /// Called from `applicationShouldTerminate`. Sends the stop and returns
    /// true when the app should wait: `completion` runs once the helper
    /// confirms, or after 1.5 seconds so a silent helper cannot hold quit
    /// hostage. Returns false when nothing needs stopping.
    ///
    /// macOS can still abandon the quit after this, for example when a logout
    /// is cancelled. If `applicationWillTerminate` does not follow within
    /// `terminationCancelGrace` of the reply, the quit is treated as
    /// cancelled: controls work again and the saved intent is reconciled.
    func prepareForTermination(completion: @escaping @MainActor @Sendable () -> Void) -> Bool {
        isTerminating = true
        terminationAttempt += 1
        let attempt = terminationAttempt
        // Keep the persisted pause: quitting mid-pause expresses no new
        // intent, so a relaunch inside the window must stay paused.
        clearPause(persistStoredPause: false)
        session.finishForTermination()
        guard protectionMayBeHeld else {
            scheduleTerminationCancelCheck(attempt: attempt)
            return false
        }

        preferences.effectiveMonitoringEnabled = false
        preferences.lastKnownState = "unknown"
        let completeAndWatch: @MainActor @Sendable () -> Void = { [weak self] in
            completion()
            self?.scheduleTerminationCancelCheck(attempt: attempt)
        }
        let finished = LockedValue(false)
        let finish: @Sendable () -> Void = {
            let first = finished.withValue { done -> Bool in
                defer { done = true }
                return !done
            }
            guard first else { return }
            Task { @MainActor in completeAndWatch() }
        }
        monitor.stopMonitoring(persistUserPreference: false) { _ in finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { finish() }
        return true
    }

    /// Last-chance cleanup from `applicationWillTerminate`, for a quit that
    /// skipped `prepareForTermination`.
    func finishForTermination() {
        let alreadyPrepared = isTerminating
        isTerminating = true
        terminationCommitted = true
        clearPause(persistStoredPause: false)
        session.finishForTermination()
        guard !alreadyPrepared, protectionMayBeHeld else { return }
        // The app cannot wait for an asynchronous XPC reply while AppKit
        // is terminating. Publish the safe visible state immediately;
        // the stop command below restores AWDL now, and the helper also
        // guarantees restoration when its final connection closes.
        preferences.effectiveMonitoringEnabled = false
        preferences.lastKnownState = "unknown"
        monitor.stopMonitoring(persistUserPreference: false)
    }

    private func scheduleTerminationCancelCheck(attempt: Int) {
        let grace = terminationCancelGrace
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, grace) * 1_000_000_000))
            self?.recoverIfTerminationCancelled(attempt: attempt)
        }
    }

    /// The quit was answered but the app is still running, so macOS
    /// abandoned it. Without this, `isTerminating` stayed set and every later
    /// attempt to turn protection on failed silently until relaunch.
    private func recoverIfTerminationCancelled(attempt: Int) {
        guard isTerminating, !terminationCommitted, attempt == terminationAttempt else { return }
        protectionExperienceLog.notice("Quit was cancelled after protection was stopped; restoring normal operation")
        isTerminating = false
        // prepareForTermination kept the stored pause; bring it back if it
        // is still running so a pause in progress is honored.
        restorePersistedPauseIfActive()
        objectWillChange.send()
        Task { await reconcileProtection() }
    }

    /// After sleep, a pause may have expired without its timer firing on
    /// time, and the helper may have restarted. Settle both.
    func handleSystemWake() async {
        objectWillChange.send()
        guard !isTerminating else { return }
        controlRefreshHandler?(.systemWake)
        if let pauseUntil {
            if pauseUntil <= Date() {
                await resumeProtection()
            } else {
                schedulePauseTimer()
            }
            return
        }
        guard transition == .idle,
              !session.isTransitioning,
              !monitor.isProtectionCommandInFlight else { return }
        await reconcileProtection()
    }

    @discardableResult
    private func startSession(
        trigger: ProtectedSessionTrigger,
        gameModeRequest: Int?
    ) async -> Bool {
        guard !isTerminating else { return false }
        if !license.canEnableProtection {
            // Without this the refusal is invisible in the log, so a session
            // that never engages has no stated cause in a field report.
            let refusalReason = license.grandfatherWindowExpired
                ? "transition period ended"
                : "no license"
            protectionExperienceLog.info(
                "Protection session refused for \(String(describing: trigger), privacy: .public): \(refusalReason, privacy: .public)"
            )
            lastError = LicenseCopy.required(transitionEnded: license.grandfatherWindowExpired)
            objectWillChange.send()
            return false
        }

        guard monitor.isHelperRegistered, session.phase == .idle else {
            lastError = monitor.isHelperRegistered
                ? nil
                : "Finish Ping Protection setup before recording a latency session."
            return false
        }

        actionGeneration += 1
        let generation = actionGeneration
        requestedSessionTrigger = trigger
        lastError = nil
        silenceMessage = nil
        clearPause()

        if !monitor.isMonitoringActive {
            beginTransition(.enablingProtection, for: generation)
            let enabled = await monitor.setProtectionEnabled(
                true,
                persistUserPreference: false
            )
            endTransition(for: generation)
            // A newer action owns protection and the error surface now.
            guard generation == actionGeneration else { return false }
            guard enabled else {
                requestedSessionTrigger = nil
                reportCommandFailure(.startSession, failure: monitor.lastCommandFailure)
                return false
            }
        }

        if let gameModeRequest,
           (!gameModeActive || gameModeRequest != gameModeGeneration) {
            requestedSessionTrigger = nil
            await reconcileProtection()
            return false
        }

        await session.start(trigger: trigger)
        guard generation == actionGeneration else {
            objectWillChange.send()
            return session.isActive
        }
        requestedSessionTrigger = nil
        let started = session.isActive
        if !started {
            lastError = session.lastError ?? "The latency session did not start."
            await reconcileProtection()
        }
        objectWillChange.send()
        return started
    }

    private func endSession(
        reason: ProtectedSessionEndReason,
        protectionWasInterrupted: Bool
    ) async {
        actionGeneration += 1
        requestedSessionTrigger = nil
        await session.stop(
            endReason: reason,
            protectionWasInterrupted: protectionWasInterrupted
        )
        await reconcileProtection()
        objectWillChange.send()
    }

    private func reconcileProtection() async {
        guard !isTerminating else { return }
        let shouldEnable = ProtectionExperiencePolicy.shouldEnableProtection(
            for: policyState,
            now: Date()
        )

        // A first enable still awaiting its reply counts as wanting
        // protection, or turning a session off mid-enable would skip the
        // stop and let the late enable leave AWDL down with no owner.
        let monitorWantsProtection = monitor.isMonitoringRequested || monitor.isProtectionDesired
        if shouldEnable == monitor.isMonitoringActive,
           shouldEnable == monitorWantsProtection {
            return
        }

        actionGeneration += 1
        let generation = actionGeneration
        beginTransition(shouldEnable ? .enablingProtection : .disablingProtection, for: generation)
        let success = await monitor.setProtectionEnabled(
            shouldEnable,
            persistUserPreference: false
        )
        endTransition(for: generation)
        guard generation == actionGeneration else { return }
        if !success {
            reportCommandFailure(shouldEnable ? .turnOn : .turnOff, failure: monitor.lastCommandFailure)
            protectionExperienceLog.error("Could not reconcile protection state to \(shouldEnable)")
        }
    }

    private func beginTransition(_ next: Transition, for generation: Int) {
        transition = next
        transitionOwner = generation
    }

    private func endTransition(for generation: Int) {
        guard transitionOwner == generation else { return }
        transition = .idle
    }

    private func reportCommandFailure(
        _ action: ProtectionFailureCopy.Action,
        failure: HelperCommandFailure?
    ) {
        let message = ProtectionFailureCopy.message(for: action, failure: failure)
        if failure?.helperDidNotAnswer == true {
            helperSilent = true
            showSilenceError(message)
            evaluateRepairOffer()
        } else {
            lastError = message
            silenceMessage = nil
            objectWillChange.send()
        }
    }

    private func showSilenceError(_ message: String) {
        lastError = message
        silenceMessage = message
        objectWillChange.send()
    }

    private func publishAutomatedError(_ message: String) {
        lastError = message
        silenceMessage = nil
        if message == ProtectionFailureCopy.lostHelperConnection {
            // The monitor gave up reconnecting: the helper is silent, so
            // Repair is offered where this message points to it.
            helperSilent = true
            silenceMessage = message
        }
        objectWillChange.send()
        evaluateRepairOffer()
    }

    /// Any reply proves the helper answers again. Clear a message that said
    /// otherwise, and when protection is wanted but was left idle because
    /// the helper was silent, try the saved intent once more.
    private func helperDidRespond() {
        let wasSilent = helperSilent
        helperSilent = false
        if let silenceMessage, lastError == silenceMessage {
            lastError = nil
        }
        silenceMessage = nil
        objectWillChange.send()
        guard wasSilent else { return }
        // The episode ends: a later failure may be offered Repair again.
        evaluateRepairOffer()
        // The helper may have restarted (and restored AWDL) while silent.
        if !isTerminating {
            controlRefreshHandler?(.helperRecovered)
        }
        // One automatic retry per minute keeps a helper that answers some
        // requests but not others from producing a retry loop.
        if let lastAutomaticRetry, Date().timeIntervalSince(lastAutomaticRetry) < 60 {
            return
        }
        guard !isTerminating,
              helperRepairTask == nil,
              transition == .idle,
              !session.isTransitioning,
              !monitor.isMonitoringRequested,
              !monitor.isMonitoringActive,
              !monitor.isProtectionCommandInFlight,
              ProtectionExperiencePolicy.shouldEnableProtection(for: policyState, now: Date()) else {
            return
        }
        lastAutomaticRetry = Date()
        protectionExperienceLog.info("Helper answered again; retrying the saved protection intent")
        Task {
            await reconcileProtection()
        }
    }

    private func schedulePauseTimer() {
        pauseTimer?.invalidate()
        guard let pauseUntil else { return }

        let timer = Timer.scheduledTimer(
            withTimeInterval: max(0, pauseUntil.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.resumeProtection()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func clearPause(persistStoredPause: Bool = true) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseUntil = nil
        if persistStoredPause {
            preferences.protectionPauseUntil = nil
        }
    }

    /// Restore a pause that was active when the app last quit or crashed, so
    /// an expiring ten-minute window is not cut short by a relaunch. Expired
    /// leftovers are cleared; protection state itself reconciles elsewhere.
    private func restorePersistedPauseIfActive() {
        guard let stored = preferences.protectionPauseUntil else { return }
        if stored > Date() {
            protectionExperienceLog.info("Restoring protection pause until \(stored, privacy: .public)")
            pauseUntil = stored
            schedulePauseTimer()
        } else {
            preferences.protectionPauseUntil = nil
        }
    }
}
