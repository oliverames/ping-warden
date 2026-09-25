//
//  InterfaceVisibilityPolicy.swift
//  PingWarden
//
//  Pure decision logic for Ping Warden's visible entry points. Control
//  Center mode replaces the menu bar icon with the Control Center toggle and
//  also hides the Dock icon, so the app has no icon at all. Opening the app
//  directly is then the way to Settings. Launches the person did not ask to
//  see, at login or from the Control Center toggle, stay silent.
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

    /// Control Center mode hides the Dock icon along with the menu bar icon,
    /// whatever the Show Dock Icon preference says. The preference itself is
    /// kept, so leaving Control Center mode restores the person's choice.
    static func isDockIconShown(showDockIconPreference: Bool, menuBarIconHidden: Bool) -> Bool {
        showDockIconPreference && !menuBarIconHidden
    }

    /// Open Settings at launch when the app has no icon and the person
    /// opened it themselves.
    static func shouldOpenSettingsAtLaunch(
        menuBarIconHidden: Bool,
        launchedAsLoginItem: Bool,
        launchedByControlCenter: Bool
    ) -> Bool {
        menuBarIconHidden && !launchedAsLoginItem && !launchedByControlCenter
    }
}
