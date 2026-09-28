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
    private var isTerminating = false

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

    /// Whether a repair is rebuilding the helper's registration. Views that
    /// offer Repair or Finish Setup disable those controls meanwhile.
    var isRepairingHelper: Bool {
        monitor.isRepairingHelper
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
                protectionTitle: "Turning On Ping Protection...",
                protectionActionEnabled: false,
                pauseTitle: nil,
                pauseActionEnabled: false,
                statusTitle: "Status: Turning On Protection"
            )
        case .disablingProtection:
            return ProtectionExperiencePolicy.MenuPresentation(
                protectionTitle: "Turning Off Ping Protection...",
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
        guard lastError == nil else { return }
        lastError = ProtectionFailureCopy.setupIncomplete
        objectWillChange.send()
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
    func prepareForTermination(completion: @escaping @MainActor @Sendable () -> Void) -> Bool {
        isTerminating = true
        // Keep the persisted pause: quitting mid-pause expresses no new
        // intent, so a relaunch inside the window must stay paused.
        clearPause(persistStoredPause: false)
        session.finishForTermination()
        guard protectionMayBeHeld else { return false }

        preferences.effectiveMonitoringEnabled = false
        preferences.lastKnownState = "unknown"
        let finished = LockedValue(false)
        let finish: @Sendable () -> Void = {
            let first = finished.withValue { done -> Bool in
                defer { done = true }
                return !done
            }
            guard first else { return }
            Task { @MainActor in completion() }
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

    /// After sleep, a pause may have expired without its timer firing on
    /// time, and the helper may have restarted. Settle both.
    func handleSystemWake() async {
        objectWillChange.send()
        guard !isTerminating else { return }
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
        objectWillChange.send()
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
        // One automatic retry per minute keeps a helper that answers some
        // requests but not others from producing a retry loop.
        if let lastAutomaticRetry, Date().timeIntervalSince(lastAutomaticRetry) < 60 {
            return
        }
        guard !isTerminating,
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
