// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import SwiftUI
import ServiceManagement

/// Opens the setup window from SwiftUI surfaces (Dashboard, Settings) that
/// cannot reach the app delegate. The delegate installs the handler.
@MainActor
enum OnboardingPresenter {
    static var handler: ((OnboardingMode) -> Void)?
    /// Installed by the delegate; see `licenseActivated()`.
    static var licenseActivationHandler: (() -> Void)?

    static func present(_ mode: OnboardingMode) {
        handler?(mode)
    }

    /// A license was just activated outside the setup window (Settings →
    /// License, which the Dashboard unlock card opens). Protection turns on
    /// when the helper is ready; otherwise setup continues at the idle
    /// Approve step, or Repair runs for an approved helper that stopped
    /// answering (`LicenseActivationFollowUp`). The setup window's own
    /// license step continues by itself and never calls this, so the
    /// window cannot open twice.
    static func licenseActivated() {
        licenseActivationHandler?()
    }
}

/// Runs the setup window: step navigation, the license field, and the
/// Approve step's live state. Step and approval decisions come from
/// `OnboardingNavigator` and `HelperApprovalTracker` in Core; this class
/// feeds them the live registration status and performs the actions.
@MainActor
final class OnboardingModel: ObservableObject {
    struct Actions {
        var openDashboard: @MainActor () -> Void = {}
        var close: @MainActor () -> Void = {}
        var bringToFront: @MainActor () -> Void = {}
    }

    @Published private(set) var navigator: OnboardingNavigator
    @Published private(set) var tracker: HelperApprovalTracker
    @Published var licenseKey = ""
    @Published private(set) var licenseMessage: String?
    @Published private(set) var licenseMessageIsError = false
    /// The coordinator's final word on a Repair, shown on Done or on the
    /// failure screen.
    @Published private(set) var repairReport: HelperTestReport?
    @Published private(set) var protectionOnAtDone = false
    @Published var showsHelperInfo = false
    @Published var showsProtectionIllustration = false
    /// Set when this Repair follows a license the person just activated:
    /// a successful Repair then turns protection on, instead of only
    /// restoring the saved choice as Repair otherwise does. Cleared when
    /// the window switches to another entry point.
    var turnsProtectionOnWhenRepaired = false

    var actions: Actions
    private var pollTimer: Timer?
    private var chartTimer: Timer?
    /// A registration or repair the window started is still running. A
    /// second press joins it instead of starting another.
    private var operationInFlight = false
    private let isPreview: Bool
    /// A preview's fixed license state; nil follows the live license.
    private let previewCanEnableProtection: Bool?

    /// Whether protection can be turned on: a valid license or an active
    /// transition. Views observe `LicenseManager` for changes.
    var canEnableProtection: Bool {
        previewCanEnableProtection ?? LicenseManager.shared.canEnableProtection
    }

    var mode: OnboardingMode { navigator.mode }
    var step: OnboardingStep { navigator.step }

    init(mode: OnboardingMode, actions: Actions = Actions()) {
        self.actions = actions
        self.isPreview = false
        self.previewCanEnableProtection = nil
        self.navigator = OnboardingNavigator(mode: mode, canEnableProtection: LicenseManager.shared.canEnableProtection)
        self.tracker = Self.freshTracker(mode: mode)
        stepDidChange()
    }

    /// A model that shows one fixed state and performs nothing, for
    /// previews and screenshots.
    init(preview mode: OnboardingMode, step: OnboardingStep, tracker: HelperApprovalTracker,
         canEnableProtection: Bool, protectionOn: Bool = false, repairReport: HelperTestReport? = nil) {
        self.actions = Actions()
        self.isPreview = true
        self.previewCanEnableProtection = canEnableProtection
        var navigator = OnboardingNavigator(mode: mode, canEnableProtection: canEnableProtection)
        navigator.show(step)
        self.navigator = navigator
        self.tracker = tracker
        self.protectionOnAtDone = protectionOn
        self.repairReport = repairReport
    }

    /// Switch an open window to another entry point, such as Repair while
    /// the introduction is showing.
    func restart(mode: OnboardingMode) {
        guard !isPreview else { return }
        stopTimers()
        navigator = OnboardingNavigator(mode: mode, canEnableProtection: LicenseManager.shared.canEnableProtection)
        if !operationInFlight {
            tracker = Self.freshTracker(mode: mode)
        }
        repairReport = nil
        turnsProtectionOnWhenRepaired = false
        stepDidChange()
    }

    /// Switch to Repair after a license was activated while Repair's check
    /// found a helper that must be approved again. Repair then ends with
    /// protection on.
    func showRepairAfterLicense() {
        guard !isPreview else { return }
        if mode != .repair {
            restart(mode: .repair)
        }
        turnsProtectionOnWhenRepaired = true
    }

    /// Show the idle Approve step after a license arrived from Settings
    /// while this window was on another screen. Finish Setup with a license
    /// starts at approval, and nothing is asked of macOS until Approve
    /// Helper is clicked.
    func showApprovalAfterLicense() {
        guard !isPreview, mode != .repair, step != .approve else { return }
        restart(mode: .finishSetup)
    }

    func windowWillClose() {
        stopTimers()
    }

    // MARK: Navigation

    func continueTapped() {
        guard !isPreview else { return }
        navigator.advance(canEnableProtection: LicenseManager.shared.canEnableProtection)
        stepDidChange()
    }

    /// Back retraces the screens shown; with nowhere to go, it closes.
    func backTapped() {
        guard !isPreview else { return }
        if navigator.canGoBack {
            navigator.goBack()
            stepDidChange()
        } else {
            actions.close()
        }
    }

    func enterLicenseTapped() {
        guard !isPreview else { return }
        navigator.show(.license)
        stepDidChange()
    }

    func openDashboardTapped() {
        guard !isPreview else { return }
        actions.openDashboard()
    }

    func closeTapped() {
        guard !isPreview else { return }
        actions.close()
    }

    func openLoginItems() {
        guard !isPreview else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    func buyLicense() {
        guard !isPreview else { return }
        NSWorkspace.shared.open(LicenseManager.purchaseURL(from: "onboarding"))
    }

    func selectIllustration(showsProtection: Bool) {
        chartTimer?.invalidate()
        chartTimer = nil
        showsProtectionIllustration = showsProtection
    }

    private func stepDidChange() {
        guard !isPreview else { return }
        chartTimer?.invalidate()
        chartTimer = nil
        switch step {
        case .approve:
            // Approval only follows a license or an active transition.
            if navigator.requireLicenseForApproval(canEnableProtection: LicenseManager.shared.canEnableProtection) {
                stepDidChange()
                return
            }
            enterApproveStep()
        case .protection:
            stopPolling()
            showsProtectionIllustration = false
            // Show the comparison on its own once, after a moment to read.
            chartTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.step == .protection else { return }
                    withAnimation(.easeInOut(duration: 0.36)) {
                        self.showsProtectionIllustration = true
                    }
                }
            }
        default:
            stopPolling()
        }
    }

    // MARK: Approve step

    private func enterApproveStep() {
        if !operationInFlight {
            tracker = Self.freshTracker(mode: mode)
        }
        startPolling()
        // An already enabled helper needs no approval: confirm it answers
        // and finish.
        if tracker.confirmsOnEntry {
            runRegistration(rebuild: false)
        }
    }

    func approvePrimaryTapped() {
        guard !isPreview else { return }
        switch tracker.primaryAction {
        case .approveHelper, .tryAgain:
            beginApproval()
        case .openSystemSettings:
            if tracker.phase == .ready {
                // An earlier request is pending; resuming it opens Login
                // Items at once and watches for the switch.
                beginApproval()
            } else {
                SMAppService.openSystemSettingsLoginItems()
            }
        case .checking:
            break
        }
    }

    func approveSecondaryTapped() {
        guard !isPreview else { return }
        switch tracker.secondaryAction {
        case .back:
            backTapped()
        case .cancel:
            if mode == .repair {
                actions.close()
            } else {
                tracker.cancel()
            }
        case .openSystemSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .none:
            break
        }
    }

    private func beginApproval() {
        tracker.start(now: Self.now)
        guard !operationInFlight else { return }
        runRegistration(rebuild: true)
    }

    /// `rebuild` is false when approval already happened (an enabled
    /// helper on entry, or a late approval): then only the helper's reply
    /// is confirmed, and an answering registration is never torn down.
    private func runRegistration(rebuild: Bool) {
        guard !operationInFlight else { return }
        operationInFlight = true
        let experience = ProtectionExperienceCoordinator.shared
        if mode == .repair {
            Task { @MainActor in
                let report = rebuild
                    ? await experience.reapproveHelper()
                    : await experience.repairHelperConnection()
                operationInFlight = false
                await handleRepairReport(report)
            }
        } else {
            // Covers a first registration, an earlier pending request, and
            // a registration that exists but never answers, and succeeds
            // only on a helper reply.
            PingWardenMonitor.shared.repairHelperRegistration(presentsErrors: false) { [weak self] registered in
                Task { @MainActor in
                    await self?.finishSetup(registered: registered)
                }
            }
        }
    }

    private func finishSetup(registered: Bool) async {
        if registered {
            // Setup is complete without a license too; only the protection
            // toggle is gated, so an unlicensed setup leaves it off.
            if LicenseManager.shared.canEnableProtection {
                _ = await ProtectionExperienceCoordinator.shared.setPersistentProtection(true)
            }
            operationInFlight = false
            showDone()
            return
        }
        operationInFlight = false
        let monitor = PingWardenMonitor.shared
        let message: String?
        if Self.liveStatus() == .enabled {
            message = "The helper was approved but is not responding. Restart your Mac, then open Settings → Advanced and click Repair."
        } else {
            message = monitor.lastSetupFailureMessage
        }
        tracker.registrationFailed(message: message)
    }

    private func handleRepairReport(_ report: HelperTestReport) async {
        var report = report
        if report.title == RepairResultCopy.successTitle,
           mode == .repair, turnsProtectionOnWhenRepaired {
            // This Repair followed a license activation, which is meant to
            // end with protection on. Repair itself restored the saved
            // choice; turn protection on through the toggle's own path.
            turnsProtectionOnWhenRepaired = false
            let decision = await ProtectionExperienceCoordinator.shared.turnOnProtectionAfterLicenseActivation()
            if decision == .turnOn {
                report = HelperTestReport(
                    title: report.title,
                    message: RepairResultCopy.successMessage(
                        protectionOn: PingWardenMonitor.shared.isMonitoringActive
                    )
                )
            }
        }
        if report.title == RepairResultCopy.failureTitle {
            if Self.liveStatus() == .enabled {
                // Approved, but the helper still does not answer.
                repairReport = report
                stopPolling()
                navigator.show(.repairFailed)
                actions.bringToFront()
            } else {
                tracker.registrationFailed(message: report.message)
            }
            return
        }
        repairReport = report
        showDone()
    }

    private func showDone() {
        protectionOnAtDone = PingWardenMonitor.shared.isMonitoringActive
        stopPolling()
        navigator.show(.done)
        actions.bringToFront()
    }

    private func pollStatus() {
        let reaction = tracker.update(
            status: Self.liveStatus(),
            now: Self.now,
            monitorOpenedLoginItems: PingWardenMonitor.shared.registrationOpenedLoginItems
        )
        if reaction == .confirmApproval {
            runRegistration(rebuild: false)
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        // The monitor reads the registration once a second while it waits;
        // this reads the same cached value at the same pace.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollStatus() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func stopTimers() {
        stopPolling()
        chartTimer?.invalidate()
        chartTimer = nil
    }

    // MARK: License step

    func activateLicense() {
        guard !isPreview else { return }
        let license = LicenseManager.shared
        let key = licenseKey
        guard !license.isVerifying, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        licenseMessage = nil
        Task { @MainActor in
            let entitled = await license.verify(key: key)
            if entitled {
                licenseMessage = "License verified. Ping Protection is available."
                licenseMessageIsError = false
                if licenseKey == key { licenseKey = "" }
                guard step == .license, mode != .repair else { return }
                // A valid key continues straight into helper approval, and
                // setup turns protection on when approval finishes. An
                // approved helper that stopped answering goes through
                // Repair's check instead.
                PingWardenMonitor.shared.refreshHelperStatus()
                let followUp = LicenseActivationFollowUp.decide(
                    canEnableProtection: LicenseManager.shared.canEnableProtection,
                    helperStatus: Self.liveStatus(),
                    helperResponding: !ProtectionExperienceCoordinator.shared.shouldOfferHelperRepair,
                    openWindow: LicenseActivationFollowUp.OpenWindow(mode: mode, step: step)
                )
                if followUp == .repairHelper {
                    await repairAfterLicense()
                } else {
                    continueTapped()
                }
            } else {
                licenseMessage = LicenseSettingsContent.message(for: license.lastVerificationResult)
                licenseMessageIsError = true
            }
        }
    }

    /// Repair's check, run in place after a license was activated on the
    /// license step while the approved helper was not answering. A helper
    /// that must be approved again switches this window to Repair, which
    /// waits for Approve Helper and ends with protection on. One that
    /// answers after all continues to approval, which confirms it, turns
    /// protection on, and shows Done.
    private func repairAfterLicense() async {
        licenseMessage = "License verified. Checking Ping Warden's helper…"
        licenseMessageIsError = false
        let check = await ProtectionExperienceCoordinator.shared.checkHelperForRepair()
        // The person may have moved on, or the app may be quitting.
        guard !ProtectionExperienceCoordinator.shared.isTerminating,
              step == .license, mode != .repair else { return }
        licenseMessage = "License verified. Ping Protection is available."
        switch check {
        case .needsApproval:
            showRepairAfterLicense()
            actions.bringToFront()
        case .finished:
            continueTapped()
        }
    }

    // MARK: Live status

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Repair reaches this step only after the helper failed to answer, so
    /// an Enabled status there is a registration to rebuild, not approval.
    private static func freshTracker(mode: OnboardingMode) -> HelperApprovalTracker {
        HelperApprovalTracker(status: liveStatus(), needsNewRegistration: mode == .repair)
    }

    static func liveStatus() -> HelperRegistrationState {
        switch PingWardenMonitor.shared.registrationStatus {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }
}
