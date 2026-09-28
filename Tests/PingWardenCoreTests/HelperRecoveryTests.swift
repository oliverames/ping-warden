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

    func testDisableIsSatisfiedWhenInterfaceIsUpAndNothingWasRequested() {
        // A fresh install whose first enable timed out records "unknown";
        // turning off must not then depend on the silent helper.
        XCTAssertTrue(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: false, lastKnownState: "unknown", interfaceUp: true
        ))
        XCTAssertTrue(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: false, lastKnownState: "up", interfaceUp: nil
        ))
    }

    func testDisableStillNeedsHelperWhenAWDLMayBeBlocked() {
        XCTAssertFalse(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: false, lastKnownState: "unknown", interfaceUp: false
        ), "a down interface may be held down by the helper")
        XCTAssertFalse(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: false, lastKnownState: "unknown", interfaceUp: nil
        ), "an unreadable interface leaves the helper as the authority")
        XCTAssertFalse(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: false, lastKnownState: "down", interfaceUp: nil
        ))
    }

    func testDisableNeedsHelperWhileProtectionIsRequestedOrActive() {
        XCTAssertFalse(HelperRecovery.disableAlreadySatisfied(
            isRequested: true, isActive: false, lastKnownState: "up", interfaceUp: true
        ))
        XCTAssertFalse(HelperRecovery.disableAlreadySatisfied(
            isRequested: false, isActive: true, lastKnownState: "up", interfaceUp: true
        ))
    }

    func testSilentRegisteredHelperStillOwesTheIntroductionOnce() {
        let suiteName = "PingWardenHelperRecoveryTests.\(UUID().uuidString)"
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
