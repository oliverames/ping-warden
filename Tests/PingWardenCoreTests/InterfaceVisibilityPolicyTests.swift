//
//  InterfaceVisibilityPolicyTests.swift
//  PingWardenCoreTests
//
//  XCTest suite for InterfaceVisibilityPolicy: how saved preferences
//  resolve to an interface mode, which icons each mode shows, and when a
//  launch must open Settings so the app stays reachable.
//

import Foundation
import XCTest
@testable import PingWardenCore

final class InterfaceVisibilityPolicyTests: XCTestCase {

    private typealias Policy = InterfaceVisibilityPolicy

    // MARK: - mode

    func testDefaultPreferencesResolveToMenuBarIcon() {
        XCTAssertEqual(Policy.mode(controlCenterOnlySaved: false, legacyHideMenuBarIconSaved: false), .menuBarIcon)
    }

    func testLegacyHideMenuBarIconIsKeptWithoutTheNewKey() {
        // A 4.2.1 user who chose Hide Menu Bar Icon has only the old key.
        XCTAssertEqual(Policy.mode(controlCenterOnlySaved: false, legacyHideMenuBarIconSaved: true), .hideMenuBarIcon)
    }

    func testControlCenterOnlyWinsOverEitherLegacyValue() {
        XCTAssertEqual(Policy.mode(controlCenterOnlySaved: true, legacyHideMenuBarIconSaved: false), .controlCenterOnly)
        XCTAssertEqual(Policy.mode(controlCenterOnlySaved: true, legacyHideMenuBarIconSaved: true), .controlCenterOnly)
    }

    func testNewKeyNameDiffersFromTheLegacyKey() {
        // Reusing the legacy key would silently change what 4.2.1 users chose.
        XCTAssertEqual(Policy.controlCenterOnlyPreferenceKey, "ControlCenterOnlyEnabled")
        XCTAssertNotEqual(Policy.controlCenterOnlyPreferenceKey, "ControlCenterWidgetEnabled")
    }

    // MARK: - Icons

    func testMenuBarIconHiddenOnlyWhenControlCenterIsUsable() {
        XCTAssertFalse(Policy.isMenuBarIconHidden(mode: .menuBarIcon, controlCenterAvailable: true))
        XCTAssertTrue(Policy.isMenuBarIconHidden(mode: .hideMenuBarIcon, controlCenterAvailable: true))
        XCTAssertTrue(Policy.isMenuBarIconHidden(mode: .controlCenterOnly, controlCenterAvailable: true))
        XCTAssertFalse(Policy.isMenuBarIconHidden(mode: .hideMenuBarIcon, controlCenterAvailable: false))
        XCTAssertFalse(Policy.isMenuBarIconHidden(mode: .controlCenterOnly, controlCenterAvailable: false))
    }

    func testEffectiveModeFallsBackToMenuBarIconWhenUnavailable() {
        XCTAssertEqual(Policy.effectiveMode(.controlCenterOnly, controlCenterAvailable: false), .menuBarIcon)
        XCTAssertEqual(Policy.effectiveMode(.hideMenuBarIcon, controlCenterAvailable: false), .menuBarIcon)
        XCTAssertEqual(Policy.effectiveMode(.controlCenterOnly, controlCenterAvailable: true), .controlCenterOnly)
    }

    func testDefaultModeDockIconFollowsPreference() {
        XCTAssertTrue(Policy.isDockIconShown(mode: .menuBarIcon, showDockIconPreference: true, controlCenterAvailable: true))
        XCTAssertFalse(Policy.isDockIconShown(mode: .menuBarIcon, showDockIconPreference: false, controlCenterAvailable: true))
        XCTAssertNil(Policy.dockIconOverride(mode: .menuBarIcon, controlCenterAvailable: true))
    }

    func testLegacyModeKeepsTheDockIconWhateverThePreference() {
        // The 4.2.1 lockout guard: no menu bar icon means the Dock icon stays.
        XCTAssertTrue(Policy.isDockIconShown(mode: .hideMenuBarIcon, showDockIconPreference: true, controlCenterAvailable: true))
        XCTAssertTrue(Policy.isDockIconShown(mode: .hideMenuBarIcon, showDockIconPreference: false, controlCenterAvailable: true))
        XCTAssertEqual(Policy.dockIconOverride(mode: .hideMenuBarIcon, controlCenterAvailable: true), true)
    }

    func testControlCenterOnlyHidesTheDockIconWhateverThePreference() {
        XCTAssertFalse(Policy.isDockIconShown(mode: .controlCenterOnly, showDockIconPreference: true, controlCenterAvailable: true))
        XCTAssertFalse(Policy.isDockIconShown(mode: .controlCenterOnly, showDockIconPreference: false, controlCenterAvailable: true))
        XCTAssertEqual(Policy.dockIconOverride(mode: .controlCenterOnly, controlCenterAvailable: true), false)
    }

    func testUnavailableControlCenterReturnsTheDockToThePreference() {
        for mode in [InterfaceVisibilityMode.hideMenuBarIcon, .controlCenterOnly] {
            XCTAssertNil(Policy.dockIconOverride(mode: mode, controlCenterAvailable: false))
            XCTAssertTrue(Policy.isDockIconShown(mode: mode, showDockIconPreference: true, controlCenterAvailable: false))
            XCTAssertFalse(Policy.isDockIconShown(mode: mode, showDockIconPreference: false, controlCenterAvailable: false))
        }
    }

    func testEveryModeLeavesAVisibleEntryPointOrOpensSettings() {
        // Lockout check: with no icon at all, a direct launch must open Settings.
        for mode in [InterfaceVisibilityMode.menuBarIcon, .hideMenuBarIcon, .controlCenterOnly] {
            for preference in [true, false] {
                for available in [true, false] {
                    let menuBarHidden = Policy.isMenuBarIconHidden(mode: mode, controlCenterAvailable: available)
                    let dockShown = Policy.isDockIconShown(mode: mode, showDockIconPreference: preference, controlCenterAvailable: available)
                    let opensSettings = Policy.shouldOpenSettingsAtLaunch(
                        mode: mode, controlCenterAvailable: available, showDockIconPreference: preference,
                        launchReason: .direct, welcomeVisible: false, licenseNoticeVisible: false
                    )
                    XCTAssertTrue(!menuBarHidden || dockShown || opensSettings, "\(mode) pref=\(preference) available=\(available)")
                }
            }
        }
    }

    // MARK: - Launch reason

    func testPlainLaunchIsDirect() {
        XCTAssertEqual(Policy.launchReason(from: LaunchSignals()), .direct)
        XCTAssertFalse(LaunchReason.direct.isSilent)
    }

    func testEachSourceProducesASilentReason() {
        XCTAssertEqual(Policy.launchReason(from: LaunchSignals(launchedAsLoginItem: true)), .loginItem)
        XCTAssertEqual(Policy.launchReason(from: LaunchSignals(launchIsDefault: false)), .sessionRestore)
        XCTAssertEqual(Policy.launchReason(from: LaunchSignals(relaunchedByUpdater: true)), .updateRelaunch)
        XCTAssertEqual(
            Policy.launchReason(from: LaunchSignals(arguments: ["/Applications/Ping Warden.app", Policy.controlCenterLaunchArgument])),
            .controlCenter
        )
        for reason in [LaunchReason.loginItem, .sessionRestore, .updateRelaunch, .controlCenter] {
            XCTAssertTrue(reason.isSilent)
        }
    }

    func testUnrelatedArgumentsStayDirect() {
        XCTAssertEqual(Policy.launchReason(from: LaunchSignals(arguments: ["-NSDocumentRevisionsDebugMode", "YES"])), .direct)
    }

    func testRecordedReasonSilencesADirectLaunch() {
        // A later source, such as a Control Center intent that launches the
        // app without the argument (#92), marks the launch after the fact.
        var state = LaunchReasonState(signals: LaunchSignals())
        XCTAssertEqual(state.reason, .direct)
        state.record(.controlCenter)
        XCTAssertEqual(state.reason, .controlCenter)
    }

    func testRecordedReasonKeepsTheFirstSilentReason() {
        var state = LaunchReasonState(signals: LaunchSignals(launchedAsLoginItem: true))
        state.record(.controlCenter)
        XCTAssertEqual(state.reason, .loginItem)
    }

    func testUpdateRelaunchMarkerExpires() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(Policy.isUpdateRelaunchMarkerFresh(markedAt: nil, now: now))
        XCTAssertTrue(Policy.isUpdateRelaunchMarkerFresh(markedAt: now.addingTimeInterval(-5), now: now))
        XCTAssertFalse(Policy.isUpdateRelaunchMarkerFresh(markedAt: now.addingTimeInterval(-900), now: now))
        // A clock that moved backwards must not make the marker last forever.
        XCTAssertFalse(Policy.isUpdateRelaunchMarkerFresh(markedAt: now.addingTimeInterval(60), now: now))
    }

    // MARK: - shouldOpenSettingsAtLaunch

    private func opensSettings(
        mode: InterfaceVisibilityMode = .controlCenterOnly,
        available: Bool = true,
        dockPreference: Bool = false,
        reason: LaunchReason = .direct,
        welcome: Bool = false,
        notice: Bool = false
    ) -> Bool {
        Policy.shouldOpenSettingsAtLaunch(
            mode: mode,
            controlCenterAvailable: available,
            showDockIconPreference: dockPreference,
            launchReason: reason,
            welcomeVisible: welcome,
            licenseNoticeVisible: notice
        )
    }

    func testDirectLaunchInControlCenterOnlyOpensSettings() {
        XCTAssertTrue(opensSettings())
        XCTAssertTrue(opensSettings(dockPreference: true))
    }

    func testSilentLaunchesStaySilent() {
        for reason in [LaunchReason.loginItem, .sessionRestore, .updateRelaunch, .controlCenter] {
            XCTAssertFalse(opensSettings(reason: reason), "\(reason)")
        }
    }

    func testLegacyAndDefaultModesNeverForceSettings() {
        // Both keep an icon, so a direct launch behaves as it did in 4.2.1.
        XCTAssertFalse(opensSettings(mode: .hideMenuBarIcon))
        XCTAssertFalse(opensSettings(mode: .hideMenuBarIcon, dockPreference: true))
        XCTAssertFalse(opensSettings(mode: .menuBarIcon))
    }

    func testUnavailableControlCenterNeverForcesSettings() {
        XCTAssertFalse(opensSettings(available: false))
    }

    func testSettingsWaitsBehindWelcomeAndLicenseNotice() {
        XCTAssertFalse(opensSettings(welcome: true))
        XCTAssertFalse(opensSettings(notice: true))
    }

    // MARK: - LaunchPresentationGate

    func testGateOpensOnceAfterBothSteps() {
        var gate = LaunchPresentationGate()
        XCTAssertFalse(gate.settle(.welcome))
        XCTAssertTrue(gate.settle(.licenseNotice))
        XCTAssertFalse(gate.settle(.welcome))
        XCTAssertFalse(gate.settle(.licenseNotice))
    }

    func testGateOrderDoesNotMatter() {
        var gate = LaunchPresentationGate()
        XCTAssertFalse(gate.settle(.licenseNotice))
        XCTAssertFalse(gate.settle(.licenseNotice))
        XCTAssertTrue(gate.settle(.welcome))
    }

    // MARK: - Copy

    func testEveryIconHidingModeExplainsItselfInBothPanes() {
        XCTAssertNil(InterfaceVisibilityCopy.automationFooter(mode: .menuBarIcon))
        XCTAssertNil(InterfaceVisibilityCopy.generalFooter(mode: .menuBarIcon))
        for mode in [InterfaceVisibilityMode.hideMenuBarIcon, .controlCenterOnly] {
            XCTAssertNotNil(InterfaceVisibilityCopy.automationFooter(mode: mode))
            XCTAssertNotNil(InterfaceVisibilityCopy.generalFooter(mode: mode))
        }
    }

    func testControlCenterOnlyCopyTellsPeopleHowToGetBack() {
        let footer = InterfaceVisibilityCopy.automationFooter(mode: .controlCenterOnly) ?? ""
        XCTAssertTrue(footer.contains("Edit Controls"))
        XCTAssertTrue(footer.contains("Spotlight"))
        XCTAssertTrue(InterfaceVisibilityCopy.confirmationMessage.contains("Spotlight"))
    }

    func testCopyAvoidsEmDashes() {
        let strings = [
            InterfaceVisibilityCopy.controlCenterOnlyDetail,
            InterfaceVisibilityCopy.confirmationMessage,
            InterfaceVisibilityCopy.legacyStatusDetail,
        ] + [InterfaceVisibilityMode.hideMenuBarIcon, .controlCenterOnly].flatMap {
            [InterfaceVisibilityCopy.automationFooter(mode: $0) ?? "", InterfaceVisibilityCopy.generalFooter(mode: $0) ?? ""]
        }
        for string in strings {
            XCTAssertFalse(string.contains("\u{2014}"), string)
        }
    }

    // MARK: - Widget parity

    func testWidgetArgumentMatchesWidgetSource() throws {
        // The widget target cannot import PingWardenCore, so it repeats the
        // literal. Guard against the two drifting apart.
        let widgetSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PingWarden/PingWardenWidget/PingWardenToggleIntent.swift")
        let source = try String(contentsOf: widgetSource, encoding: .utf8)
        XCTAssertTrue(source.contains("\"\(Policy.controlCenterLaunchArgument)\""))
    }
}
