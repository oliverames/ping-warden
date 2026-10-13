import Foundation
import XCTest
@testable import PingWardenCore

final class OnboardingNavigatorTests: XCTestCase {
    func testLicensedFirstRunHasFourScreens() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: true)
        XCTAssertEqual(nav.step, .welcome)
        XCTAssertEqual(nav.pageSteps, [.welcome, .protection, .approve, .done])
        XCTAssertFalse(nav.canGoBack, "Welcome closes with Not Now")
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .protection)
        nav.advance(canEnableProtection: true)
        XCTAssertEqual(nav.step, .approve, "a licensed person never sees the license step")
        XCTAssertEqual(nav.pageIndex, 2)
        nav.goBack()
        XCTAssertEqual(nav.step, .protection)
    }

    func testUnlicensedFirstRunAsksForTheLicenseBeforeApproval() {
        var nav = OnboardingNavigator(mode: .firstRun, canEnableProtection: false)
        XCTAssertEqual(nav.pageSteps, [.welcome, .protection, .license, .approve, .done])
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
        XCTAssertEqual(nav.pageSteps.count, 5, "dots do not jump while the window is open")
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
