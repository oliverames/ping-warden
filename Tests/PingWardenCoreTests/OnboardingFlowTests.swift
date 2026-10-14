import Foundation
import XCTest
@testable import PingWardenCore

final class OnboardingNavigatorTests: XCTestCase {
    func testLicensedFirstRunHasFourScreens() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: true)
        XCTAssertEqual(nav.step, .welcome)
        XCTAssertEqual(nav.pageSteps, [.protection, .approve, .done], "the Welcome keeps its own layout without dots")
        XCTAssertNil(nav.pageIndex)
        XCTAssertFalse(nav.canGoBack, "Welcome closes with Not Now")
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .protection)
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve, "a licensed person never sees the license step")
        XCTAssertEqual(nav.pageIndex, 1)
        nav.goBack()
        XCTAssertEqual(nav.step, .protection)
    }

    func testUnlicensedFirstRunAsksForTheLicenseBeforeApproval() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: false)
        XCTAssertEqual(nav.pageSteps, [.protection, .license, .approve, .done])
        nav.advance(canEnableProtection: false)
        nav.advance(canEnableProtection: false)
        XCTAssertEqual(nav.step, .license)
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve, "an activated license continues to approval")
        nav.goBack()
        XCTAssertEqual(nav.step, .license)
    }

    func testSkipForNowEndsOnTheFreeDashboard() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: false)
        nav.advance(canEnableProtection: false)
        nav.advance(canEnableProtection: false)
        nav.advance(canEnableProtection: false)
        XCTAssertEqual(nav.step, .freeDashboard, "nobody approves a helper they cannot use yet")
        XCTAssertEqual(nav.pageIndex, nav.pageSteps.count - 1)
        nav.goBack()
        XCTAssertEqual(nav.step, .license)
    }

    func testFinishSetupResumesAtTheFirstIncompleteStep() {
        XCTAssertEqual(OnboardingNavigator(mode: .finishSetup, canEnableProtection: false).step, .license)
        let licensed = OnboardingNavigator(mode: .finishSetup, canEnableProtection: true)
        XCTAssertEqual(licensed.step, .approve)
        XCTAssertFalse(licensed.canGoBack, "Finish Setup does not replay the welcome")
        XCTAssertEqual(licensed.pageSteps, [.approve, .done])
    }

    func testRepairStartsAtApprovalWithoutDots() {
        let nav = OnboardingNavigator(mode: .repair, canEnableProtection: false)
        XCTAssertEqual(nav.step, .approve, "Repair never asks for a license")
        XCTAssertEqual(nav.pageSteps, [])
        XCTAssertNil(nav.pageIndex)
        XCTAssertFalse(nav.canGoBack, "Back becomes Cancel in Repair")
    }

    func testApprovalWaitsForALicense() {
        var nav = OnboardingNavigator(mode: .finishSetup, canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve)
        XCTAssertTrue(nav.requireLicenseForApproval(canEnableProtection: false),
                      "a license that lapsed sends approval back to the license step")
        XCTAssertEqual(nav.step, .license)
        XCTAssertFalse(nav.requireLicenseForApproval(canEnableProtection: false), "only the Approve step redirects")
        var licensed = OnboardingNavigator(mode: .finishSetup, canEnableProtection: true)
        XCTAssertFalse(licensed.requireLicenseForApproval(canEnableProtection: true))
        XCTAssertEqual(licensed.step, .approve)
        var repair = OnboardingNavigator(mode: .repair, canEnableProtection: false)
        XCTAssertFalse(repair.requireLicenseForApproval(canEnableProtection: false), "Repair fixes an approved helper")
        XCTAssertEqual(repair.step, .approve)
    }

    func testUnlicensedPathNeverReachesApproval() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: false)
        var visited: [OnboardingStep] = [nav.step]
        for _ in 0..<5 {
            nav.advance(canEnableProtection: false)
            visited.append(nav.step)
        }
        XCTAssertFalse(visited.contains(.approve))
        XCTAssertEqual(nav.step, .freeDashboard)
    }

    func testDoneClearsHistory() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: true)
        nav.advance(canEnableProtection: true)
        nav.advance(canEnableProtection: true)
        nav.show(.done)
        XCTAssertEqual(nav.step, .done)
        XCTAssertFalse(nav.canGoBack)
        nav.goBack()
        XCTAssertEqual(nav.step, .done)
    }

    func testLicenseStepVisibilityIsFixedAtOpen() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: false)
        nav.advance(canEnableProtection: true)
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve, "a license added mid-flow skips the license screen")
        XCTAssertEqual(nav.pageSteps.count, 4, "dots do not jump while the window is open")
    }
}

final class HelperApprovalTrackerTests: XCTestCase {
    private let modern = SystemSettingsCopy.Variant.appBackgroundActivity

    func testReadyAsksBeforeMacOSShowsAnything() {
        let tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        XCTAssertEqual(tracker.phase, .ready)
        XCTAssertEqual(tracker.primaryAction, .approveHelper)
        XCTAssertEqual(tracker.secondaryAction, .back)
        XCTAssertEqual(tracker.cards, [.upcoming, .upcoming, .upcoming])
        XCTAssertTrue(tracker.statusLine.detail.contains("Nothing changes until you click Approve Helper"))
        XCTAssertFalse(tracker.confirmsOnEntry)
    }

    func testAlreadyEnabledHelperSkipsApproval() {
        let tracker = HelperApprovalTracker(status: .enabled, variant: modern)
        XCTAssertTrue(tracker.confirmsOnEntry)
        XCTAssertEqual(tracker.phase, .confirming)
        XCTAssertEqual(tracker.cards, [.complete, .complete, .complete])
        XCTAssertEqual(tracker.primaryAction, .checking)
    }

    func testEarlierRequestOpensSystemSettingsAtOnce() {
        var tracker = HelperApprovalTracker(status: .requiresApproval, variant: modern)
        XCTAssertEqual(tracker.primaryAction, .openSystemSettings)
        XCTAssertEqual(tracker.cards, [.complete, .current, .upcoming])
        XCTAssertTrue(tracker.statusLine.detail.contains("earlier request is waiting"))
        tracker.start(now: 100)
        XCTAssertTrue(tracker.resumedEarlierRequest)
        XCTAssertTrue(tracker.loginItemsOpened, "registerHelper opens Login Items at once for an earlier request")
        XCTAssertEqual(tracker.statusLine.detail, "Opened System Settings for you. Turn on Ping Warden, then confirm.")
    }

    func testFreshRegistrationSaysSystemSettingsOpensAfterTenSeconds() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        XCTAssertEqual(tracker.phase, .waiting)
        XCTAssertEqual(tracker.secondaryAction, .cancel)
        XCTAssertEqual(tracker.primaryAction, .openSystemSettings)
        XCTAssertTrue(tracker.statusLine.detail.contains("after 10 seconds, System Settings opens for you"))
        tracker.update(status: .requiresApproval, now: 1)
        XCTAssertEqual(tracker.cards, [.complete, .current, .upcoming])
        XCTAssertTrue(tracker.animatesSwitchHint)
        tracker.update(status: .requiresApproval, now: 10, monitorOpenedLoginItems: true)
        XCTAssertTrue(tracker.statusLine.detail.hasPrefix("Opened System Settings for you"))
    }

    func testStillWaitingHintAtFortyFiveSeconds() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.update(status: .requiresApproval, now: 44.9)
        XCTAssertFalse(tracker.statusLine.detail.hasPrefix("Still waiting"))
        tracker.update(status: .requiresApproval, now: 45)
        XCTAssertEqual(tracker.statusLine.detail, "Still waiting. This stops in a few seconds.")
        XCTAssertEqual(tracker.phase, .waiting)
    }

    func testTimeoutAtSixtySecondsOffersTryAgain() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.update(status: .requiresApproval, now: 60)
        XCTAssertEqual(tracker.phase, .timedOut)
        XCTAssertEqual(tracker.primaryAction, .tryAgain)
        XCTAssertEqual(tracker.secondaryAction, .openSystemSettings)
        XCTAssertEqual(tracker.statusLine.title, "Approval did not arrive")
        XCTAssertTrue(tracker.statusLine.detail.contains("App Background Activity"))
        let legacy = HelperApprovalTracker(status: .notRegistered, variant: .loginItems)
        var older = legacy
        older.start(now: 0)
        older.update(status: .requiresApproval, now: 61)
        XCTAssertTrue(older.statusLine.detail.contains("Allow in the Background"))
    }

    func testLateApprovalAfterTimeoutStillAdvances() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.update(status: .requiresApproval, now: 61)
        tracker.registrationFailed(message: "did not get approval in time")
        XCTAssertEqual(tracker.phase, .timedOut, "the monitor's own timeout keeps the timed-out screen")
        XCTAssertEqual(tracker.update(status: .requiresApproval, now: 65), .none)
        XCTAssertEqual(tracker.update(status: .enabled, now: 70), .confirmApproval)
        XCTAssertEqual(tracker.phase, .confirming)
        XCTAssertEqual(tracker.cards, [.complete, .complete, .complete])
    }

    func testApprovalDuringTheWaitIsConfirmedByTheRunningPoll() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        XCTAssertEqual(tracker.update(status: .enabled, now: 5), .none,
                       "the registration already in flight confirms the reply itself")
        XCTAssertEqual(tracker.phase, .confirming)
        XCTAssertEqual(tracker.statusLine.title, "Approved")
        XCTAssertEqual(tracker.secondaryAction, .none)
    }

    func testCancelKeepsWatching() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.update(status: .requiresApproval, now: 2)
        tracker.cancel()
        XCTAssertEqual(tracker.phase, .ready)
        XCTAssertEqual(tracker.primaryAction, .openSystemSettings, "the pending request only needs the switch")
        tracker.registrationFailed(message: "late failure")
        XCTAssertEqual(tracker.phase, .ready, "a cancelled wait is not turned into an error")
        XCTAssertEqual(tracker.update(status: .enabled, now: 20), .confirmApproval)
    }

    func testRegistrationErrorShowsItsMessage() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.registrationFailed(message: "Ping Warden could not register its helper. Try again. Boom")
        XCTAssertEqual(tracker.phase, .failed(message: "Ping Warden could not register its helper. Try again. Boom"))
        XCTAssertEqual(tracker.primaryAction, .tryAgain)
        XCTAssertEqual(tracker.statusLine.tone, .warning)
        tracker.start(now: 30)
        XCTAssertEqual(tracker.phase, .waiting, "Try Again starts a new attempt")
        XCTAssertEqual(tracker.elapsed, 0)
    }

    func testRepairOfASilentHelperWaitsForApproveHelper() {
        var tracker = HelperApprovalTracker(status: .enabled, variant: modern, needsNewRegistration: true)
        XCTAssertFalse(tracker.confirmsOnEntry, "a silent helper's Enabled status is not an approval")
        XCTAssertEqual(tracker.phase, .ready)
        XCTAssertEqual(tracker.primaryAction, .approveHelper, "the person is warned before macOS shows anything")
        XCTAssertEqual(tracker.cards, [.upcoming, .upcoming, .upcoming])
        XCTAssertEqual(tracker.update(status: .enabled, now: 1), .none, "polling the old registration starts nothing")
        tracker.start(now: 10)
        XCTAssertEqual(tracker.phase, .waiting)
        XCTAssertFalse(tracker.resumedEarlierRequest)
        tracker.update(status: .enabled, now: 11)
        XCTAssertEqual(tracker.phase, .waiting, "the old registration is not mistaken for approval")
        tracker.update(status: .notRegistered, now: 12)
        XCTAssertFalse(tracker.needsNewRegistration)
        tracker.update(status: .requiresApproval, now: 13)
        XCTAssertEqual(tracker.cards, [.complete, .current, .upcoming])
        tracker.update(status: .enabled, now: 20)
        XCTAssertEqual(tracker.phase, .confirming, "the rebuilt registration's approval counts")
    }

    func testRepairOfAnUnapprovedHelperIsAnOrdinaryApproval() {
        let tracker = HelperApprovalTracker(status: .requiresApproval, variant: modern, needsNewRegistration: true)
        XCTAssertFalse(tracker.needsNewRegistration)
        XCTAssertEqual(tracker.primaryAction, .openSystemSettings)
    }

    func testFailureWhileApprovalPendingIsATimeout() {
        var tracker = HelperApprovalTracker(status: .notRegistered, variant: modern)
        tracker.start(now: 0)
        tracker.update(status: .requiresApproval, now: 59)
        tracker.registrationFailed(message: nil)
        XCTAssertEqual(tracker.phase, .timedOut)
    }
}

final class OnboardingCopyTests: XCTestCase {
    func testDoneCopyFollowsProtectionAndLicense() {
        XCTAssertEqual(OnboardingCopy.done(mode: .firstRun, protectionOn: true, canEnableProtection: true).title, "Ping Protection is on")
        let unlicensed = OnboardingCopy.done(mode: .firstRun, protectionOn: false, canEnableProtection: false)
        XCTAssertEqual(unlicensed.title, "Helper is ready")
        XCTAssertFalse(unlicensed.isComplete)
        XCTAssertTrue(unlicensed.body.contains("license"))
        XCTAssertEqual(OnboardingCopy.done(mode: .repair, protectionOn: true, canEnableProtection: true).title, "Helper repaired")
    }

    func testRepairCopyNamesItself() {
        XCTAssertEqual(OnboardingCopy.approveTitle(mode: .repair), "Approve the helper again")
        XCTAssertEqual(OnboardingCopy.approveTitle(mode: .firstRun), "Approve the helper")
        XCTAssertTrue(OnboardingCopy.approveSubtitle(mode: .repair).contains("settings and history stay"))
    }

    func testCopyAvoidsEmDashesAndAllowWording() {
        var strings = [
            OnboardingCopy.welcomeTitle, OnboardingCopy.welcomeLine, OnboardingCopy.welcomeReassurance,
            OnboardingCopy.protectionBody, OnboardingCopy.protectionCaption, OnboardingCopy.licenseBody,
            OnboardingCopy.trustLine, OnboardingCopy.freeDashboardBody,
        ]
        strings += OnboardingCopy.cardCaptions + OnboardingCopy.helperFacts
        for string in strings {
            XCTAssertFalse(string.contains("\u{2014}"), string)
            XCTAssertFalse(string.contains("..."), string)
        }
        // The pre-alert button must not imitate the system's own Allow.
        XCTAssertFalse(OnboardingCopy.cardCaptions.joined().contains("Allow"))
    }
}

final class LicenseActivationFollowUpTests: XCTestCase {
    private typealias Window = LicenseActivationFollowUp.OpenWindow
    private static let notApproved: [HelperRegistrationState] = [.notRegistered, .requiresApproval, .notFound]

    private func decide(
        licensed: Bool = true,
        _ status: HelperRegistrationState,
        responding: Bool = true,
        window: Window? = nil
    ) -> LicenseActivationFollowUp {
        LicenseActivationFollowUp.decide(
            canEnableProtection: licensed,
            helperStatus: status,
            helperResponding: responding,
            openWindow: window
        )
    }

    // MARK: Ready helper

    func testLicensedWithAReadyHelperTurnsProtectionOnWithoutAWindow() {
        XCTAssertEqual(decide(.enabled), .turnProtectionOn)
    }

    func testAReadyHelperLeavesAnOpenWindowWhereItIs() {
        for window in [
            Window(mode: .firstRun, step: .freeDashboard),
            Window(mode: .firstRun, step: .welcome),
            Window(mode: .finishSetup, step: .license),
            Window(mode: .finishSetup, step: .done),
        ] {
            XCTAssertEqual(decide(.enabled, window: window), .turnProtectionOn, "\(window)")
        }
    }

    // MARK: Helper not approved yet

    func testLicensedWithoutAnApprovedHelperOpensApproval() {
        for status in Self.notApproved {
            XCTAssertEqual(decide(status), .openApproval, "\(status)")
            // Silence does not matter before approval: approval comes first.
            XCTAssertEqual(decide(status, responding: false), .openApproval, "\(status)")
        }
    }

    func testOpeningApprovalLandsOnTheIdleApproveStep() {
        // The window opens as Finish Setup with a license, which starts at
        // approval rather than the Welcome or the protection explainer.
        let nav = OnboardingNavigator(mode: .finishSetup, canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve)
        XCTAssertEqual(nav.pageSteps, [.approve, .done])
        // Nothing has been asked of macOS until Approve Helper.
        for status in [HelperRegistrationState.notRegistered, .notFound] {
            let tracker = HelperApprovalTracker(status: status, variant: .appBackgroundActivity)
            XCTAssertEqual(tracker.phase, .ready)
            XCTAssertEqual(tracker.primaryAction, .approveHelper)
            XCTAssertFalse(tracker.confirmsOnEntry)
        }
        let pending = HelperApprovalTracker(status: .requiresApproval, variant: .appBackgroundActivity)
        XCTAssertEqual(pending.phase, .ready)
        XCTAssertFalse(pending.confirmsOnEntry)
    }

    func testProtectionTurnsOnAfterApproval() {
        // Approval finishing hands a licensed person to protection on: the
        // follow-up after approval sees an enabled, answering helper, and
        // the protection decision for a fresh setup is to turn it on.
        XCTAssertEqual(decide(.enabled), .turnProtectionOn)
        XCTAssertEqual(
            LicenseActivationProtection.decide(.init(
                canEnableProtection: true, protectionOn: false, savedChoiceOn: false,
                pauseActive: false, sessionActive: false, changeInFlight: false
            )),
            .turnOn
        )
        // Approval leads to Done, the screen that reports protection on.
        var nav = OnboardingNavigator(mode: .finishSetup, canEnableProtection: true)
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .done)
    }

    func testAnOpenWindowSwitchesToApprovalInsteadOfOpeningASecond() {
        for step in [OnboardingStep.welcome, .protection, .license, .freeDashboard] {
            XCTAssertEqual(
                decide(.notRegistered, window: Window(mode: .firstRun, step: step)),
                .showApprovalInOpenWindow,
                "\(step)"
            )
        }
        XCTAssertEqual(
            decide(.requiresApproval, window: Window(mode: .finishSetup, step: .license)),
            .showApprovalInOpenWindow
        )
    }

    func testAnOpenWindowAlreadyApprovingIsOnlyBroughtForward() {
        XCTAssertEqual(
            decide(.requiresApproval, window: Window(mode: .finishSetup, step: .approve)),
            .bringOpenWindowForward
        )
        XCTAssertEqual(
            decide(.notRegistered, window: Window(mode: .repair, step: .approve)),
            .bringOpenWindowForward,
            "a Repair in progress is never restarted"
        )
    }

    // MARK: Approved but not answering

    func testAnEnabledButSilentHelperGoesToRepair() {
        XCTAssertEqual(decide(.enabled, responding: false), .repairHelper)
    }

    func testRepairFromAnOpenWindowOnAnotherScreenRunsInPlace() {
        // Repair's check runs first; the window switches to Repair in
        // place only if the helper must be approved again. No second window.
        for window in [
            Window(mode: .firstRun, step: .welcome),
            Window(mode: .firstRun, step: .license),
            Window(mode: .finishSetup, step: .license),
            Window(mode: .firstRun, step: .freeDashboard),
            Window(mode: .finishSetup, step: .done),
        ] {
            XCTAssertEqual(decide(.enabled, responding: false, window: window), .repairHelper, "\(window)")
        }
    }

    func testAnOpenRepairOrApprovalIsOnlyBroughtForwardForASilentHelper() {
        for window in [
            Window(mode: .repair, step: .approve),
            Window(mode: .repair, step: .repairFailed),
            Window(mode: .repair, step: .done),
            Window(mode: .finishSetup, step: .approve),
            Window(mode: .firstRun, step: .approve),
        ] {
            XCTAssertEqual(
                decide(.enabled, responding: false, window: window),
                .bringOpenWindowForward,
                "\(window)"
            )
        }
    }

    func testRepairStartsAtTheIdleApproveStepWithNothingAskedOfMacOS() {
        // A helper that must be approved again opens Repair at its idle
        // Approve step, waiting for the person's click.
        let nav = OnboardingNavigator(mode: .repair, canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve)
        let tracker = HelperApprovalTracker(status: .enabled, needsNewRegistration: true)
        XCTAssertFalse(tracker.confirmsOnEntry)
    }

    // MARK: Unlicensed

    func testUnlicensedDoesNothing() {
        for status in Self.notApproved + [.enabled] {
            for responding in [true, false] {
                XCTAssertEqual(decide(licensed: false, status, responding: responding), .none)
                for window in [
                    Window(mode: .firstRun, step: .license),
                    Window(mode: .repair, step: .approve),
                ] {
                    XCTAssertEqual(
                        decide(licensed: false, status, responding: responding, window: window),
                        .none
                    )
                }
            }
        }
    }
}

final class LicenseActivationProtectionTests: XCTestCase {
    private func decide(
        licensed: Bool = true,
        on: Bool = false,
        saved: Bool = false,
        paused: Bool = false,
        session: Bool = false,
        inFlight: Bool = false
    ) -> LicenseActivationProtection {
        LicenseActivationProtection.decide(.init(
            canEnableProtection: licensed,
            protectionOn: on,
            savedChoiceOn: saved,
            pauseActive: paused,
            sessionActive: session,
            changeInFlight: inFlight
        ))
    }

    func testAnActivatedLicenseTurnsProtectionOn() {
        XCTAssertEqual(decide(), .turnOn)
        // Saved as on but not running (for example after a helper restart).
        XCTAssertEqual(decide(saved: true), .turnOn)
        // Running but not saved as on: saving the choice is still needed.
        XCTAssertEqual(decide(on: true), .turnOn)
    }

    func testAlreadyOnIsLeftAlone() {
        XCTAssertEqual(decide(on: true, saved: true), .alreadyOn)
    }

    func testUnlicensedNeverTurnsOn() {
        XCTAssertEqual(decide(licensed: false), .notLicensed)
        XCTAssertEqual(decide(licensed: false, paused: true, session: true, inFlight: true), .notLicensed)
    }

    func testAPauseIsKept() {
        XCTAssertEqual(decide(saved: true, paused: true), .pauseActive)
    }

    func testASessionIsLeftAlone() {
        XCTAssertEqual(decide(on: true, session: true), .sessionActive)
        XCTAssertEqual(decide(paused: true, session: true), .sessionActive)
    }

    func testAChangeInFlightIsNotSuperseded() {
        XCTAssertEqual(decide(inFlight: true), .changeInFlight)
        XCTAssertEqual(decide(session: true, inFlight: true), .changeInFlight)
    }
}
