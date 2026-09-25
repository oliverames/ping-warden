//
//  InterfaceVisibilityPolicyTests.swift
//  PingWardenCoreTests
//
//  XCTest suite for InterfaceVisibilityPolicy: when the menu bar icon is
//  hidden and when a launch must open Settings so the app stays reachable.
//

import Foundation
import XCTest
@testable import PingWardenCore

final class InterfaceVisibilityPolicyTests: XCTestCase {

    // MARK: - isMenuBarIconHidden

    func testMenuBarIconHiddenOnlyWhenControlCenterModeIsUsable() {
        XCTAssertTrue(InterfaceVisibilityPolicy.isMenuBarIconHidden(controlCenterModeEnabled: true, controlCenterAvailable: true))
        XCTAssertFalse(InterfaceVisibilityPolicy.isMenuBarIconHidden(controlCenterModeEnabled: true, controlCenterAvailable: false))
        XCTAssertFalse(InterfaceVisibilityPolicy.isMenuBarIconHidden(controlCenterModeEnabled: false, controlCenterAvailable: true))
    }

    // MARK: - isDockIconShown

    func testControlCenterModeHidesDockIconRegardlessOfPreference() {
        XCTAssertFalse(InterfaceVisibilityPolicy.isDockIconShown(showDockIconPreference: true, menuBarIconHidden: true))
        XCTAssertFalse(InterfaceVisibilityPolicy.isDockIconShown(showDockIconPreference: false, menuBarIconHidden: true))
    }

    func testDockIconFollowsPreferenceWithMenuBarIcon() {
        XCTAssertTrue(InterfaceVisibilityPolicy.isDockIconShown(showDockIconPreference: true, menuBarIconHidden: false))
        XCTAssertFalse(InterfaceVisibilityPolicy.isDockIconShown(showDockIconPreference: false, menuBarIconHidden: false))
    }

    // MARK: - shouldOpenSettingsAtLaunch

    func testDirectLaunchInControlCenterModeOpensSettings() {
        XCTAssertTrue(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, launchedAsLoginItem: false, launchedByControlCenter: false
        ))
    }

    func testLoginLaunchStaysSilent() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, launchedAsLoginItem: true, launchedByControlCenter: false
        ))
    }

    func testControlCenterLaunchStaysSilent() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, launchedAsLoginItem: false, launchedByControlCenter: true
        ))
    }

    func testMenuBarIconNeverForcesSettings() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: false, launchedAsLoginItem: false, launchedByControlCenter: false
        ))
    }

    func testWidgetArgumentMatchesWidgetSource() throws {
        // The widget target cannot import PingWardenCore, so it repeats the
        // literal. Guard against the two drifting apart.
        let widgetSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PingWarden/PingWardenWidget/PingWardenToggleIntent.swift")
        let source = try String(contentsOf: widgetSource, encoding: .utf8)
        XCTAssertTrue(source.contains("\"\(InterfaceVisibilityPolicy.controlCenterLaunchArgument)\""))
    }
}
