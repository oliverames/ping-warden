import Foundation
import XCTest
@testable import PingWardenCore

final class SystemSettingsCopyTests: XCTestCase {
    func testLoginItemsPaneFollowsTheMacOS15Rename() {
        XCTAssertEqual(SystemSettingsCopy.loginItemsPaneName(osMajorVersion: 13), "Login Items")
        XCTAssertEqual(SystemSettingsCopy.loginItemsPaneName(osMajorVersion: 14), "Login Items")
        XCTAssertEqual(SystemSettingsCopy.loginItemsPaneName(osMajorVersion: 15), "Login Items & Extensions")
        XCTAssertEqual(SystemSettingsCopy.loginItemsPaneName(osMajorVersion: 26), "Login Items & Extensions")
        XCTAssertEqual(SystemSettingsCopy.loginItemsPath(osMajorVersion: 14),
                       "System Settings → General → Login Items")
        XCTAssertEqual(SystemSettingsCopy.loginItemsPath(osMajorVersion: 15),
                       "System Settings → General → Login Items & Extensions")
    }

    func testCurrentPaneNameMatchesThisMac() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(SystemSettingsCopy.loginItemsPaneName,
                       SystemSettingsCopy.loginItemsPaneName(osMajorVersion: major))
        XCTAssertEqual(SystemSettingsCopy.backgroundSectionName,
                       SystemSettingsCopy.backgroundSectionName(osMajorVersion: major))
        XCTAssertEqual(SystemSettingsCopy.variant, SystemSettingsCopy.Variant(osMajorVersion: major))
        XCTAssertTrue(ProtectionFailureCopy.setupIncomplete.contains(SystemSettingsCopy.loginItemsPaneName))
    }

    /// Apple's Login Items guide names the switch section Allow in the
    /// Background on macOS 13 through 15 and App Background Activity on
    /// macOS 26 and later.
    func testBackgroundSectionFollowsTheMacOS26Rename() {
        for version in [13, 14, 15] {
            XCTAssertEqual(SystemSettingsCopy.backgroundSectionName(osMajorVersion: version), "Allow in the Background")
        }
        for version in [26, 27] {
            XCTAssertEqual(SystemSettingsCopy.backgroundSectionName(osMajorVersion: version), "App Background Activity")
        }
    }

    func testVariantsCoverThreeLayouts() {
        XCTAssertEqual(SystemSettingsCopy.Variant(osMajorVersion: 13), .loginItems)
        XCTAssertEqual(SystemSettingsCopy.Variant(osMajorVersion: 14), .loginItems)
        XCTAssertEqual(SystemSettingsCopy.Variant(osMajorVersion: 15), .loginItemsAndExtensions)
        XCTAssertEqual(SystemSettingsCopy.Variant(osMajorVersion: 26), .appBackgroundActivity)
        XCTAssertEqual(SystemSettingsCopy.Variant(osMajorVersion: 27), .appBackgroundActivity)
    }

    func testBreadcrumbAndInstructionNameThePaneAndSection() {
        XCTAssertEqual(SystemSettingsCopy.switchBreadcrumb(osMajorVersion: 14),
                       ["System Settings", "General", "Login Items", "Allow in the Background"])
        XCTAssertEqual(SystemSettingsCopy.switchBreadcrumb(osMajorVersion: 15),
                       ["System Settings", "General", "Login Items & Extensions", "Allow in the Background"])
        XCTAssertEqual(SystemSettingsCopy.switchBreadcrumb(osMajorVersion: 26),
                       ["System Settings", "General", "Login Items & Extensions", "App Background Activity"])
        XCTAssertEqual(SystemSettingsCopy.turnOnInstruction(osMajorVersion: 26),
                       "Turn on Ping Warden under App Background Activity in System Settings → General → Login Items & Extensions")
        XCTAssertEqual(SystemSettingsCopy.turnOnInstruction(osMajorVersion: 13),
                       "Turn on Ping Warden under Allow in the Background in System Settings → General → Login Items")
    }
}

final class LicenseCopyTests: XCTestCase {
    func testRejectedKeyCopyBlamesNeitherTypoNorRefund() {
        let copy = LicenseCopy.keyNotAccepted
        XCTAssertTrue(copy.hasPrefix("Gumroad did not accept this key."))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("refund"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("cancel"))
        XCTAssertTrue(copy.contains(LicenseCopy.supportEmail))
    }

    func testRequiredCopyStatesThePriceOnce() {
        for copy in [LicenseCopy.required, LicenseCopy.transitionEnded,
                     LicenseCopy.stayedOffAtLaunch(transitionEnded: false),
                     LicenseCopy.stayedOffAtLaunch(transitionEnded: true)] {
            XCTAssertEqual(copy.components(separatedBy: "$15").count - 1, 1, copy)
            XCTAssertEqual(copy.components(separatedBy: "Settings → License").count - 1, 1, copy)
        }
        XCTAssertEqual(LicenseCopy.required(transitionEnded: false), LicenseCopy.required)
        XCTAssertTrue(LicenseCopy.required(transitionEnded: true).hasPrefix("The transition period has ended."))
    }

    /// The menu and Settings detect a license refusal by this word.
    func testLicenseMessagesMentionALicense() {
        for copy in [LicenseCopy.required, LicenseCopy.transitionEnded, LicenseCopy.revoked,
                     LicenseCopy.stayedOffAtLaunch(transitionEnded: true)] {
            XCTAssertTrue(copy.contains("license"), copy)
        }
    }
}

final class HelperTestReportTests: XCTestCase {
    func testHealthyCheckKeepsTheHelpersPlainMessage() {
        let message = "The helper answered (version 4.2.1). Ping Protection is on."
        let report = HelperTestReport.make(helperRegistered: true, isHealthy: true, message: message)
        XCTAssertEqual(report.title, "Helper Is Working")
        XCTAssertEqual(report.message, message)
    }

    func testUnregisteredHelperPointsToFinishSetup() {
        let report = HelperTestReport.make(helperRegistered: false, isHealthy: false, message: "The helper is not set up.")
        XCTAssertEqual(report, .notSetUp)
        XCTAssertTrue(report.message.contains("Finish Setup"))
    }

    func testAWDLStillUpIsNotReportedAsASilentHelper() {
        let stillUp = HelperRecovery.interfaceHealth(protectionRequested: true, interfaceUp: true).summary
        XCTAssertEqual(HelperTestReport.make(helperRegistered: true, isHealthy: false, message: stillUp), .awdlStillActive)
    }

    func testSilentOrRejectingHelperGetsOneRecoveryPath() {
        for message in [
            "No connection to the helper could be made.",
            "The helper did not respond: \(HelperCommandFailure.timedOut.diagnosticDescription).",
            "The helper did not respond: \(HelperCommandFailure.rejected(code: 4099).diagnosticDescription)."
        ] {
            let report = HelperTestReport.make(helperRegistered: true, isHealthy: false, message: message)
            XCTAssertEqual(report, .notResponding)
            XCTAssertFalse(report.message.contains("XPC"))
            XCTAssertFalse(report.message.localizedCaseInsensitiveContains("restart the app"))
        }
    }

    func testRepairCopyMatchesProtectionState() {
        XCTAssertEqual(RepairResultCopy.successMessage(protectionOn: true), "Ping Protection is on.")
        XCTAssertEqual(RepairResultCopy.successMessage(protectionOn: false), "Ping Protection is off.")
        XCTAssertTrue(RepairResultCopy.failureMessage.contains(SystemSettingsCopy.loginItemsPath))
    }
}

final class GatekeeperCopyTests: XCTestCase {
    func testControlClickOpenIsOfferedOnlyWhereMacOSStillHasIt() {
        for version in [13, 14] {
            let copy = GatekeeperCopy.message(osMajorVersion: version)
            XCTAssertTrue(copy.contains("Control-click"), "macOS \(version)")
            XCTAssertTrue(copy.contains("Open Anyway"), "macOS \(version)")
        }
        for version in [15, 26] {
            let copy = GatekeeperCopy.message(osMajorVersion: version)
            XCTAssertFalse(copy.contains("Control-click"), "macOS \(version)")
            XCTAssertTrue(copy.contains("Privacy & Security"), "macOS \(version)")
            XCTAssertTrue(copy.contains("Open Anyway"), "macOS \(version)")
        }
    }
}

final class SettingsCopyStyleTests: XCTestCase {
    func testCopyAvoidsEmDashesAndThreeDotEllipses() {
        let copies = [
            LicenseCopy.required, LicenseCopy.transitionEnded, LicenseCopy.revoked, LicenseCopy.keyNotAccepted,
            HelperTestReport.notSetUp.message, HelperTestReport.notResponding.message,
            HelperTestReport.awdlStillActive.message, RepairResultCopy.failureMessage,
            GatekeeperCopy.message(osMajorVersion: 14), GatekeeperCopy.message(osMajorVersion: 15)
        ]
        for copy in copies {
            XCTAssertFalse(copy.contains("\u{2014}"), copy)
            XCTAssertFalse(copy.contains("..."), copy)
        }
    }
}

/// The Game Mode detector replaces its idle timer only when the interval
/// for the next tick differs from the running one, so a quiet streak must
/// change tier exactly once, at the threshold.
final class GameModeIdleTierTests: XCTestCase {
    func testQuietStreakChangesTierOnce() {
        var current = GameModePollingPolicy.interval(isActive: false, idleStreakTicks: 0)
        var changes = 0
        for ticks in 1...(GameModePollingPolicy.idleStreakThreshold * 3) {
            let next = GameModePollingPolicy.interval(isActive: false, idleStreakTicks: ticks)
            if next != current {
                changes += 1
                XCTAssertEqual(ticks, GameModePollingPolicy.idleStreakThreshold)
                current = next
            }
        }
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(current, GameModePollingPolicy.idleInterval)
    }
}
