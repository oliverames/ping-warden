// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

// Decisions for the setup window: which screen comes next, what Back does,
// and what the Approve step shows while macOS waits for approval. Kept
// Foundation-only so every transition is unit tested without AppKit.

/// Why the setup window opened.
enum OnboardingMode: Equatable, Sendable {
    /// The automatic first-run introduction, or Finish Setup before the
    /// introduction was ever seen.
    case firstRun
    /// Finish Setup from the menu, Dashboard, or Settings. Resumes at the
    /// first incomplete step rather than replaying the introduction.
    case finishSetup
    /// Repair found a helper that must be registered and approved again.
    case repair
}

enum OnboardingStep: String, Equatable, Sendable, CaseIterable {
    case welcome
    /// What Ping Protection does.
    case protection
    /// Shown only when protection cannot be turned on yet.
    case license
    /// Approve the helper. Shared by first run, Finish Setup, and Repair.
    case approve
    case done
    /// The end of the unlicensed path after Skip for Now.
    case freeDashboard
    /// Repair could not get the helper to answer after approval.
    case repairFailed
}

/// Moves between steps. Back retraces the screens actually shown, so a
/// person who skipped a step never lands on it by going back.
struct OnboardingNavigator: Equatable, Sendable {
    let mode: OnboardingMode
    private(set) var step: OnboardingStep
    private(set) var history: [OnboardingStep] = []
    /// Fixed when the window opens, so the page dots do not jump when a
    /// license is activated partway through.
    let showsLicenseStep: Bool

    init(mode: OnboardingMode, canEnableProtection: Bool) {
        self.mode = mode
        self.showsLicenseStep = mode != .repair && !canEnableProtection
        self.step = Self.entryStep(mode: mode, canEnableProtection: canEnableProtection)
    }

    /// Where a mode starts. Finish Setup resumes at the first incomplete
    /// step: the license when protection cannot be turned on yet,
    /// otherwise approval.
    static func entryStep(mode: OnboardingMode, canEnableProtection: Bool) -> OnboardingStep {
        switch mode {
        case .firstRun: return .welcome
        case .finishSetup: return canEnableProtection ? .approve : .license
        case .repair: return .approve
        }
    }

    /// The screen after `step` when the person continues.
    static func step(after step: OnboardingStep, canEnableProtection: Bool) -> OnboardingStep {
        switch step {
        case .welcome: return .protection
        case .protection: return canEnableProtection ? .approve : .license
        // Approving a helper that cannot be used yet adds a system prompt
        // for no benefit, so an unlicensed person ends on the dashboard.
        case .license: return canEnableProtection ? .approve : .freeDashboard
        case .approve: return .done
        case .done, .freeDashboard, .repairFailed: return step
        }
    }

    /// The step dots: the screens this mode walks through. Repair shows
    /// none, because it is one step rather than a sequence.
    var pageSteps: [OnboardingStep] {
        switch mode {
        case .repair:
            return []
        case .firstRun:
            return [.welcome, .protection] + (showsLicenseStep ? [.license] : []) + [.approve, .done]
        case .finishSetup:
            return (showsLicenseStep ? [.license] : []) + [.approve, .done]
        }
    }

    /// The highlighted dot. The free-dashboard ending stands in for Done.
    var pageIndex: Int? {
        let steps = pageSteps
        guard !steps.isEmpty else { return nil }
        if step == .freeDashboard { return steps.count - 1 }
        return steps.firstIndex(of: step)
    }

    /// Whether Back has somewhere to go. When it does not, the left
    /// button closes the window instead (Not Now or Cancel).
    var canGoBack: Bool {
        guard step != .done, step != .repairFailed else { return false }
        return !history.isEmpty
    }

    mutating func advance(canEnableProtection: Bool) {
        let next = Self.step(after: step, canEnableProtection: canEnableProtection)
        guard next != step else { return }
        history.append(step)
        step = next
    }

    /// Jump to a step the flow reaches on its own, such as Done after
    /// approval or the Repair failure screen.
    mutating func show(_ target: OnboardingStep) {
        guard target != step else { return }
        if target == .done || target == .repairFailed {
            history.removeAll()
        } else {
            history.append(step)
        }
        step = target
    }

    mutating func goBack() {
        guard canGoBack, let previous = history.popLast() else { return }
        step = previous
    }
}

/// The helper's registration as SMAppService reports it. Mirrors
/// `SMAppService.Status` so this file stays Foundation-only.
enum HelperRegistrationState: Equatable, Sendable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
}

/// The Approve step's live state, driven by polling the registration
/// status that the monitor already reads once a second. Timing mirrors the
/// monitor: Login Items opens 10 seconds after a fresh registration if
/// approval is still pending, and the registration poll gives up at 60
/// seconds. After that the step keeps watching, so a late approval still
/// advances.
struct HelperApprovalTracker: Equatable, Sendable {
    static let loginItemsHandoffDelay: TimeInterval = 10
    static let stillWaitingAfter: TimeInterval = 45
    static let timeout: TimeInterval = 60

    enum Phase: Equatable, Sendable {
        /// Nothing has been asked of macOS yet.
        case ready
        /// Registration was submitted and approval is pending.
        case waiting
        /// Approval arrived; the helper's reply is being confirmed.
        case confirming
        /// The 60-second window passed without approval. Still watching.
        case timedOut
        /// Registration failed for a reason other than waiting.
        case failed(message: String)
    }

    /// What the step should do after a status update.
    enum Reaction: Equatable, Sendable {
        case none
        /// Approval arrived while nothing was running, for example after a
        /// timeout or from System Settings directly. Confirm the helper.
        case confirmApproval
    }

    enum CardState: Equatable, Sendable {
        case upcoming
        case current
        case complete
    }

    enum PrimaryAction: Equatable, Sendable {
        case approveHelper
        case openSystemSettings
        case tryAgain
        /// Shown disabled while the helper's reply is confirmed.
        case checking
    }

    enum SecondaryAction: Equatable, Sendable {
        /// Back, or Cancel when there is nothing to go back to.
        case back
        /// Stop showing the wait. macOS keeps the pending request.
        case cancel
        case openSystemSettings
        /// Disabled while confirming.
        case none
    }

    enum Tone: Equatable, Sendable {
        case neutral
        case progress
        case success
        case warning
    }

    struct StatusLine: Equatable, Sendable {
        let title: String?
        let detail: String
        let tone: Tone
    }

    private(set) var phase: Phase
    private(set) var status: HelperRegistrationState
    private(set) var startedAt: TimeInterval?
    private(set) var elapsed: TimeInterval = 0
    /// The request resumed one macOS already holds, so Login Items opened
    /// at once and no new notification appears.
    private(set) var resumedEarlierRequest = false
    private(set) var loginItemsOpened = false
    /// Repair found an enabled registration whose helper never answers, so
    /// it must be registered again. Until macOS reports the old
    /// registration gone, an Enabled status is not an approval.
    private(set) var needsNewRegistration: Bool
    let variant: SystemSettingsCopy.Variant

    /// An already enabled helper skips the approval itself: the step only
    /// confirms that it answers. Repair passes `needsNewRegistration` for a
    /// silent helper, whose Enabled status proves nothing.
    init(
        status: HelperRegistrationState,
        variant: SystemSettingsCopy.Variant = SystemSettingsCopy.variant,
        needsNewRegistration: Bool = false
    ) {
        self.status = status
        self.variant = variant
        self.needsNewRegistration = needsNewRegistration && status == .enabled
        self.phase = status == .enabled && !self.needsNewRegistration ? .confirming : .ready
    }

    /// The status as the step presents it. A silent registration awaiting
    /// rebuild reads as not registered.
    var effectiveStatus: HelperRegistrationState {
        needsNewRegistration && status == .enabled ? .notRegistered : status
    }

    /// Whether entering the step should confirm the helper right away.
    var confirmsOnEntry: Bool { phase == .confirming && startedAt == nil }

    /// The person pressed the primary button. Registration starts, or an
    /// earlier pending request is resumed in Login Items.
    mutating func start(now: TimeInterval) {
        startedAt = now
        elapsed = 0
        if effectiveStatus == .enabled {
            phase = .confirming
            return
        }
        resumedEarlierRequest = effectiveStatus == .requiresApproval
        // registerHelper() opens Login Items at once for an earlier request.
        loginItemsOpened = resumedEarlierRequest
        phase = .waiting
    }

    /// Stop showing the wait. The registration poll keeps running, so an
    /// approval that arrives later still finishes setup.
    mutating func cancel() {
        guard phase == .waiting else { return }
        phase = .ready
    }

    /// One poll of the live status. `monitorOpenedLoginItems` reports the
    /// monitor's own handoff, which is what actually opens Login Items.
    @discardableResult
    mutating func update(
        status newStatus: HelperRegistrationState,
        now: TimeInterval,
        monitorOpenedLoginItems: Bool = false
    ) -> Reaction {
        status = newStatus
        if needsNewRegistration {
            if newStatus == .enabled {
                // The old registration is still in place; keep counting.
                if phase == .waiting, let startedAt {
                    elapsed = max(0, now - startedAt)
                    if elapsed >= Self.timeout { phase = .timedOut }
                }
                return .none
            }
            needsNewRegistration = false
        }
        switch phase {
        case .waiting:
            if let startedAt { elapsed = max(0, now - startedAt) }
            if monitorOpenedLoginItems { loginItemsOpened = true }
            if newStatus == .enabled {
                // The running registration poll confirms the reply itself.
                phase = .confirming
                return .none
            }
            if elapsed >= Self.timeout {
                phase = .timedOut
            }
            return .none
        case .ready, .timedOut, .failed:
            if newStatus == .enabled {
                phase = .confirming
                return .confirmApproval
            }
            return .none
        case .confirming:
            return .none
        }
    }

    /// The registration attempt ended without a confirmed helper.
    mutating func registrationFailed(message: String?) {
        switch phase {
        case .waiting, .confirming:
            if effectiveStatus == .requiresApproval || elapsed >= Self.timeout {
                phase = .timedOut
            } else {
                phase = .failed(message: message ?? "Ping Warden could not register its helper. Try again.")
            }
        case .ready, .timedOut, .failed:
            // A cancelled or already finished wait keeps its screen.
            break
        }
    }

    // MARK: Presentation

    /// The three preview cards: macOS announces the helper, turn on the
    /// switch, confirm with Touch ID or a password.
    var cards: [CardState] {
        if phase == .confirming || effectiveStatus == .enabled {
            return [.complete, .complete, .complete]
        }
        if effectiveStatus == .requiresApproval {
            return [.complete, .current, .upcoming]
        }
        if phase == .waiting {
            return [.current, .upcoming, .upcoming]
        }
        return [.upcoming, .upcoming, .upcoming]
    }

    /// Whether the switch card animates its hint.
    var animatesSwitchHint: Bool { cards[1] == .current }

    var primaryAction: PrimaryAction {
        switch phase {
        case .ready: return effectiveStatus == .requiresApproval ? .openSystemSettings : .approveHelper
        case .waiting: return .openSystemSettings
        case .confirming: return .checking
        case .timedOut, .failed: return .tryAgain
        }
    }

    var secondaryAction: SecondaryAction {
        switch phase {
        case .ready, .failed: return .back
        case .waiting: return .cancel
        case .confirming: return .none
        case .timedOut: return .openSystemSettings
        }
    }

    var statusLine: StatusLine {
        switch phase {
        case .ready:
            return StatusLine(
                title: nil,
                detail: effectiveStatus == .requiresApproval
                    ? "An earlier request is waiting. It only needs the switch turned on."
                    : "Ready when you are. Nothing changes until you click Approve Helper.",
                tone: .neutral
            )
        case .waiting:
            let detail: String
            if elapsed >= Self.stillWaitingAfter {
                detail = "Still waiting. This stops in a few seconds."
            } else if loginItemsOpened {
                detail = "Opened System Settings for you. Turn on Ping Warden, then confirm."
            } else {
                detail = "Turn on Ping Warden when macOS asks. If approval is still pending after 10 seconds, System Settings opens for you."
            }
            return StatusLine(title: "Waiting for your approval", detail: detail, tone: .progress)
        case .confirming:
            return StatusLine(title: "Approved", detail: "Checking that the helper answers…", tone: .success)
        case .timedOut:
            return StatusLine(
                title: "Approval did not arrive",
                detail: "Turn on Ping Warden under \(variant.backgroundSectionName), then click Try Again. Ping Warden keeps watching in the meantime.",
                tone: .warning
            )
        case .failed(let message):
            return StatusLine(title: "Setup did not finish", detail: message, tone: .warning)
        }
    }
}

/// Copy for the setup window that depends on state.
enum OnboardingCopy {
    static let welcomeTitle = "Welcome to Ping Warden"
    static let welcomeLine = "Keep your Wi\u{2011}Fi steady while you cloud game on a Mac."
    static let welcomeReassurance = "Setup takes about a minute and needs one approval from macOS."
    static let crashReportCaption = "Ping Warden sends anonymous crash reports. You can turn this off in Settings → Advanced."

    static let protectionTitle = "What Ping Protection does"
    static let protectionBody = "AirDrop and AirPlay use a wireless interface called AWDL. When it wakes up, your Wi\u{2011}Fi can stutter. Ping Protection keeps it paused while you play."
    static let protectionCaption = "Illustration. Other causes of lag can still affect your connection. Pause protection any time to use AirDrop, AirPlay, and Handoff."

    static let licenseTitle = "Add your license"
    static let licenseBody = "Ping Protection is a one-time $15 purchase. The latency dashboard stays free."
    static let licenseDonorNote = "Donated before version 4? Email \(LicenseCopy.supportEmail)."

    static func approveTitle(mode: OnboardingMode) -> String {
        mode == .repair ? "Approve the helper again" : "Approve the helper"
    }

    static func approveSubtitle(mode: OnboardingMode) -> String {
        mode == .repair
            ? "macOS needs your approval again. Your settings and history stay as they are."
            : "Ping Warden needs your approval once. Here is what macOS will show."
    }

    static let cardCaptions = [
        "macOS announces the helper",
        "Turn on Ping Warden",
        "Confirm with Touch ID or password",
    ]

    static let trustLine = "The helper only switches awdl0 off and on. It never reads your traffic or connects to the internet."

    static let helperFacts = [
        "Lowers awdl0 while Ping Protection is on, and raises it again when you pause or quit.",
        "Accepts requests only from Ping Warden.",
        "Never reads your traffic.",
        "Never connects to the internet.",
    ]

    struct Done: Equatable, Sendable {
        let title: String
        let body: String
        /// Green for working protection, amber when a license is missing.
        let isComplete: Bool
    }

    static func done(mode: OnboardingMode, protectionOn: Bool, canEnableProtection: Bool) -> Done {
        if mode == .repair {
            return Done(
                title: "Helper repaired",
                body: RepairResultCopy.successMessage(protectionOn: protectionOn)
                    + " Your settings and history stay as they are.",
                isComplete: true
            )
        }
        if protectionOn {
            return Done(
                title: "Ping Protection is on",
                body: "Ping Warden lives in your menu bar. Click its icon to pause protection or open the dashboard.",
                isComplete: true
            )
        }
        if canEnableProtection {
            return Done(
                title: "Helper is ready",
                body: "Ping Protection is off. Turn it on from the menu bar icon or the dashboard.",
                isComplete: true
            )
        }
        return Done(
            title: "Helper is ready",
            body: "Ping Protection turns on once you add a license. Until then, the dashboard shows your latency for free.",
            isComplete: false
        )
    }

    static let freeDashboardTitle = "You are set up for the free dashboard"
    static let freeDashboardBody = "To turn on Ping Protection, add a license in Settings → License, then choose Finish Setup to approve the helper."

    static let repairFailedTitle = "Helper still not responding"
}
