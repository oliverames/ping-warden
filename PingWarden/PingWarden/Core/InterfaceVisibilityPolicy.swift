//
//  InterfaceVisibilityPolicy.swift
//  PingWarden
//
//  Pure decision logic for Ping Warden's visible entry points. People can
//  hide the menu bar icon (using the Control Center toggle instead) and the
//  Dock icon at the same time. The app then has no icon at all, so opening
//  it directly must show Settings or there is no way back in. Launches the
//  person did not ask to see, at login or from the Control Center toggle,
//  stay silent.
//

import Foundation

enum InterfaceVisibilityPolicy {
    /// Passed by the widget when it launches the app to own the helper
    /// connection. Must match `PingProtectionIntentHandler` in the widget.
    static let controlCenterLaunchArgument = "--launched-by-control-center"

    /// The menu bar icon is hidden only while Control Center mode is on and
    /// the control can actually be used; otherwise the icon is the fallback.
    static func isMenuBarIconHidden(controlCenterModeEnabled: Bool, controlCenterAvailable: Bool) -> Bool {
        controlCenterModeEnabled && controlCenterAvailable
    }

    /// Whether any always-visible way into the app remains.
    static func hasVisibleEntryPoint(menuBarIconHidden: Bool, showDockIcon: Bool) -> Bool {
        !menuBarIconHidden || showDockIcon
    }

    /// Open Settings at launch when nothing else would show the app: no menu
    /// bar icon, no Dock icon, and the person opened the app themselves.
    static func shouldOpenSettingsAtLaunch(
        menuBarIconHidden: Bool,
        showDockIcon: Bool,
        launchedAsLoginItem: Bool,
        launchedByControlCenter: Bool
    ) -> Bool {
        guard !hasVisibleEntryPoint(menuBarIconHidden: menuBarIconHidden, showDockIcon: showDockIcon) else {
            return false
        }
        return !launchedAsLoginItem && !launchedByControlCenter
    }
}
