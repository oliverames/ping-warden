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

    // MARK: - hasVisibleEntryPoint

    func testEitherIconIsAnEntryPoint() {
        XCTAssertTrue(InterfaceVisibilityPolicy.hasVisibleEntryPoint(menuBarIconHidden: false, showDockIcon: false))
        XCTAssertTrue(InterfaceVisibilityPolicy.hasVisibleEntryPoint(menuBarIconHidden: true, showDockIcon: true))
        XCTAssertFalse(InterfaceVisibilityPolicy.hasVisibleEntryPoint(menuBarIconHidden: true, showDockIcon: false))
    }

    // MARK: - shouldOpenSettingsAtLaunch

    func testDirectLaunchWithNoIconsOpensSettings() {
        XCTAssertTrue(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, showDockIcon: false,
            launchedAsLoginItem: false, launchedByControlCenter: false
        ))
    }

    func testLoginLaunchWithNoIconsStaysSilent() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, showDockIcon: false,
            launchedAsLoginItem: true, launchedByControlCenter: false
        ))
    }

    func testControlCenterLaunchWithNoIconsStaysSilent() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, showDockIcon: false,
            launchedAsLoginItem: false, launchedByControlCenter: true
        ))
    }

    func testVisibleIconNeverForcesSettings() {
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: false, showDockIcon: false,
            launchedAsLoginItem: false, launchedByControlCenter: false
        ))
        XCTAssertFalse(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            menuBarIconHidden: true, showDockIcon: true,
            launchedAsLoginItem: false, launchedByControlCenter: false
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
