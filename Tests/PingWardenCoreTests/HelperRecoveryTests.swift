import Foundation
import XCTest
@testable import PingWardenCore

final class HelperRecoveryTests: XCTestCase {
    func testInterfaceFlagsReadUpAndDown() {
        XCTAssertEqual(
            HelperRecovery.interfaceIsUp(flagsLine: "awdl0: flags=8943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1484"),
            true
        )
        XCTAssertEqual(
            HelperRecovery.interfaceIsUp(flagsLine: "awdl0: flags=8902<BROADCAST,PROMISC,SIMPLEX,MULTICAST> mtu 1484"),
            false
        )
    }

    func testInterfaceFlagsIgnoreLookalikeFlags() {
        // POINTOPOINT and similar names contain other flags' letters; only an
        // exact UP token counts.
        XCTAssertEqual(
            HelperRecovery.interfaceIsUp(flagsLine: "awdl0: flags=8810<POINTOPOINT,SIMPLEX,MULTICAST> mtu 1484"),
            false
        )
    }

    func testUnreadableInterfaceIsUnknown() {
        XCTAssertNil(HelperRecovery.interfaceIsUp(flagsLine: "ifconfig: interface awdl0 does not exist"))
        XCTAssertNil(HelperRecovery.interfaceIsUp(flagsLine: "Error: The file couldn't be opened."))
        XCTAssertNil(HelperRecovery.interfaceIsUp(flagsLine: ""))
    }

    func testOffSucceedsWithoutHelperOnlyWhenNothingWasHeldAndAWDLIsUp() {
        // A fresh install whose first enable timed out has nothing held;
        // turning off must not then depend on the silent helper.
        XCTAssertTrue(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: false, wasActive: false, enablePending: false, interfaceUp: true
        ))
    }

    func testOffStillNeedsHelperWhenAWDLMayBeBlocked() {
        XCTAssertFalse(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: false, wasActive: false, enablePending: false, interfaceUp: false
        ), "a down interface may be held down by the helper")
        XCTAssertFalse(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: false, wasActive: false, enablePending: false, interfaceUp: nil
        ), "an unreadable interface leaves the helper as the authority")
    }

    func testOffNeedsHelperWhileProtectionIsRequestedActiveOrPending() {
        XCTAssertFalse(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: true, wasActive: false, enablePending: false, interfaceUp: true
        ))
        XCTAssertFalse(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: false, wasActive: true, enablePending: false, interfaceUp: true
        ))
        XCTAssertFalse(HelperRecovery.offSatisfiedWithoutHelper(
            wasRequested: false, wasActive: false, enablePending: true, interfaceUp: true
        ), "a first enable still in flight could land after the Off")
    }

    func testHealthCheckDoesNotCallAMissingInterfaceStillUp() {
        let missing = HelperRecovery.interfaceHealth(
            protectionRequested: true,
            interfaceUp: HelperRecovery.interfaceIsUp(flagsLine: "ifconfig: interface awdl0 does not exist")
        )
        XCTAssertTrue(missing.isHealthy)
        XCTAssertFalse(missing.summary.contains("still up"))

        let stillUp = HelperRecovery.interfaceHealth(protectionRequested: true, interfaceUp: true)
        XCTAssertFalse(stillUp.isHealthy)
        XCTAssertTrue(stillUp.summary.contains("still up"))

        XCTAssertTrue(HelperRecovery.interfaceHealth(protectionRequested: false, interfaceUp: true).isHealthy)
        XCTAssertTrue(HelperRecovery.interfaceHealth(protectionRequested: true, interfaceUp: false).isHealthy)
    }

    func testOnlyADeclinedCommandMeansTheHelperAnswered() {
        XCTAssertFalse(HelperCommandFailure.declined.helperDidNotAnswer)
        XCTAssertTrue(HelperCommandFailure.timedOut.helperDidNotAnswer)
        XCTAssertTrue(HelperCommandFailure.noConnection.helperDidNotAnswer)
        XCTAssertTrue(HelperCommandFailure.rejected(code: 4099).helperDidNotAnswer)
        XCTAssertTrue(HelperCommandFailure.rejected(code: 4099).diagnosticDescription.contains("rejected the connection"))
        XCTAssertTrue(HelperCommandFailure.rejected(code: 4097).diagnosticDescription.contains("interrupted"))
        XCTAssertTrue(HelperCommandFailure.timedOut.diagnosticDescription.contains("timed out"))
    }

    func testFailureCopyReservesQuitAdviceForAHelperThatAnswered() {
        for action in [ProtectionFailureCopy.Action.turnOff, .pause] {
            let silent = ProtectionFailureCopy.message(for: action, failure: .timedOut)
            XCTAssertFalse(silent.contains("Quit"), "\(action): a silent helper does not restore on quit")
            XCTAssertTrue(silent.contains("click Repair"))
            XCTAssertTrue(ProtectionFailureCopy.message(for: action, failure: .declined).contains("Quit"))
        }
        XCTAssertTrue(ProtectionFailureCopy.message(for: .turnOn, failure: .rejected(code: 4099)).contains("not responding"))
        XCTAssertTrue(ProtectionFailureCopy.lostHelperConnection.contains("click Repair"))
        XCTAssertFalse(ProtectionFailureCopy.lostHelperConnection.contains("restart the app"))
    }

    func testFailureCopyAvoidsEmDashes() {
        let copies = [
            ProtectionFailureCopy.helperNotResponding,
            ProtectionFailureCopy.lostHelperConnection,
            ProtectionFailureCopy.restoreAfterReconnectFailed,
            ProtectionFailureCopy.setupIncomplete
        ] + [ProtectionFailureCopy.Action.turnOn, .turnOff, .pause, .startSession].flatMap { action in
            [HelperCommandFailure.timedOut, .declined, nil].map { ProtectionFailureCopy.message(for: action, failure: $0) }
        }
        for copy in copies {
            XCTAssertFalse(copy.contains("\u{2014}"), copy)
        }
    }

    func testSilentRegisteredHelperStillOwesTheIntroductionOnce() {
        let suiteName = TestDefaultsSuite.name("PingWardenHelperRecoveryTests")
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // The app treats a registered helper that never answers as not set up.
        let state = WelcomePresentationState(defaults: defaults)
        XCTAssertTrue(state.shouldPresentAutomatically(helperIsRegistered: false))
        state.markPresented()
        XCTAssertFalse(state.shouldPresentAutomatically(helperIsRegistered: false))
    }
}

final class DiagnosticsLocationTests: XCTestCase {
    private let home = "/Users/example"

    func testAppLocationCategoriesNeverIncludeTheAccountName() {
        XCTAssertEqual(DiagnosticsPrivacy.appLocation(bundlePath: "/Applications/Ping Warden.app", homeDirectory: home), "applications")
        XCTAssertEqual(DiagnosticsPrivacy.appLocation(bundlePath: "/Users/example/Applications/Ping Warden.app", homeDirectory: home), "user_applications")
        XCTAssertEqual(DiagnosticsPrivacy.appLocation(bundlePath: "/Users/example/Downloads/Ping Warden.app", homeDirectory: home + "/"), "downloads")
        XCTAssertEqual(DiagnosticsPrivacy.appLocation(bundlePath: "/Volumes/Ping Warden/Ping Warden.app", homeDirectory: home), "disk_image_or_external_volume")
        XCTAssertEqual(
            DiagnosticsPrivacy.appLocation(
                bundlePath: "/private/var/folders/xy/abc/T/AppTranslocation/1234-ABCD/d/Ping Warden.app",
                homeDirectory: home
            ),
            "translocated"
        )
        XCTAssertEqual(DiagnosticsPrivacy.appLocation(bundlePath: "/Users/example/Desktop/Ping Warden.app", homeDirectory: home), "other")
    }

    func testLaunchdSummaryKeepsOnlyWhitelistedTopLevelKeys() {
        let output = """
        system/com.amesvt.pingwarden.helper = {
        \tactive count = 0
        \tpath = (submitted by smd.370)
        \tstate = not running
        \tprogram identifier = Contents/MacOS/PingWardenHelper (mode: 2)
        \tparent bundle version = 42100
        \tenvironment = {
        \t\tstate = nested-value-must-be-ignored
        \t}
        \truns = 3
        \tlast exit code = 78: EX_CONFIG
        \tspawn type = daemon (3)
        \tjob state = spawn failed
        }
        """
        XCTAssertEqual(
            DiagnosticsPrivacy.launchdJobSummary(launchctlOutput: output, exitStatus: 0),
            "state=not running; job state=spawn failed; runs=3; last exit code=78: EX_CONFIG; "
                + "program identifier=Contents/MacOS/PingWardenHelper (mode: 2); spawn type=daemon (3); "
                + "parent bundle version=42100"
        )
    }

    func testLaunchdSummaryReportsAMissingJob() {
        XCTAssertEqual(
            DiagnosticsPrivacy.launchdJobSummary(
                launchctlOutput: "Could not find service \"com.amesvt.pingwarden.helper\" in domain for system",
                exitStatus: 113
            ),
            "not_loaded (launchctl exit 113)"
        )
    }

    func testLaunchdSummaryDoesNotMistakeOtherFailuresForAMissingJob() {
        XCTAssertEqual(
            DiagnosticsPrivacy.launchdJobSummary(launchctlOutput: "", exitStatus: 1),
            "unavailable (launchctl exit 1)"
        )
    }
}
