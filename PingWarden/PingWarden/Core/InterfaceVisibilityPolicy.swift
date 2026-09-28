//
//  InterfaceVisibilityPolicy.swift
//  PingWarden
//
//  Pure decision logic for Ping Warden's visible entry points. Control
//  Center Only replaces the menu bar icon with the Control Center toggle and
//  also hides the Dock icon, so the app has no icon at all. Opening the app
//  directly is then the way to Settings. Launches the person did not ask to
//  see, such as login, session restore, an update relaunch, or the Control
//  Center toggle, stay silent.
//
//  Version 4.2.1 and earlier had a different setting, Hide Menu Bar Icon,
//  saved under `ControlCenterWidgetEnabled`. It hid only the menu bar icon
//  and kept the Dock icon on. People who chose it keep exactly that until
//  they pick another option, so the new mode lives under its own key and
//  the old value is never reinterpreted.
//

import Foundation

/// Which icons Ping Warden shows, resolved from the saved preferences.
enum InterfaceVisibilityMode: Equatable, Sendable {
    /// The default: a menu bar icon, and a Dock icon when Show Dock Icon is on.
    case menuBarIcon
    /// Hide Menu Bar Icon from 4.2.1 and earlier: no menu bar icon, and the
    /// Dock icon stays on so Settings is always one click away.
    case hideMenuBarIcon
    /// No menu bar or Dock icon. The Control Center toggle is the control,
    /// and opening the app from Finder or Spotlight opens Settings.
    case controlCenterOnly
}

/// Why this process was started, as far as the app can tell.
enum LaunchReason: Equatable, Sendable {
    /// The person opened the app from Finder, Spotlight, or Launchpad.
    case direct
    /// `SMAppService.mainApp` started the app at login.
    case loginItem
    /// macOS relaunched the app to restore saved state, for example through
    /// "Reopen windows when logging back in".
    case sessionRestore
    /// Sparkle relaunched the app after installing an update.
    case updateRelaunch
    /// The Control Center toggle started the app to reach the helper.
    case controlCenter

    /// Only a launch the person started should put a window on screen.
    var isSilent: Bool { self != .direct }
}

/// What the app observed about its own launch. Each field is one source of
/// a launch reason, read once in `applicationDidFinishLaunching`.
struct LaunchSignals: Equatable, Sendable {
    /// The launch Apple event carried `keyAELaunchedAsLogInItem`.
    var launchedAsLoginItem = false
    /// `NSApplication.launchIsDefaultUserInfoKey` from the launch
    /// notification. It is false when macOS relaunched the app to restore
    /// saved state or to open something, and true (or absent) otherwise.
    var launchIsDefault = true
    /// The process arguments, retained for launches from older callers.
    var arguments: [String] = []
    /// A fresh marker left by `updaterWillRelaunchApplication`.
    var relaunchedByUpdater = false
    /// A one-use App Group hint from the sandboxed Control Center widget.
    var launchedByControlCenter = false
}

/// Holds the launch reason for this process. Sources that learn about the
/// launch later than `applicationDidFinishLaunching` call `record(_:)`
/// before the launch decision runs.
struct LaunchReasonState: Equatable, Sendable {
    private(set) var reason: LaunchReason

    init(signals: LaunchSignals) {
        reason = InterfaceVisibilityPolicy.launchReason(from: signals)
    }

    /// A silent reason replaces `.direct`. An earlier silent reason is kept,
    /// because any one of them is enough to stay silent.
    mutating func record(_ newReason: LaunchReason) {
        guard reason == .direct else { return }
        reason = newReason
    }
}

/// Launch opens Settings only after every earlier launch window has had its
/// chance, so Settings never lands on top of the welcome window or the
/// license notice. Each step settles exactly once.
struct LaunchPresentationGate: Equatable, Sendable {
    enum Step: Sendable {
        /// The welcome decision, including the helper launch probe.
        case welcome
        /// The first license-notice decision at launch.
        case licenseNotice
    }

    private(set) var welcomeSettled = false
    private(set) var licenseNoticeSettled = false
    private(set) var hasOpened = false

    /// Returns true exactly once: when the last outstanding step settles.
    mutating func settle(_ step: Step) -> Bool {
        switch step {
        case .welcome: welcomeSettled = true
        case .licenseNotice: licenseNoticeSettled = true
        }
        guard welcomeSettled, licenseNoticeSettled, !hasOpened else { return false }
        hasOpened = true
        return true
    }
}

enum InterfaceVisibilityPolicy {
    /// Retained for compatibility. Sandboxed widgets use the App Group hint
    /// because NSWorkspace ignores their launch arguments.
    static let controlCenterLaunchArgument = "--launched-by-control-center"

    /// Saved by the new Control Center Only toggle. The legacy key,
    /// `ControlCenterWidgetEnabled`, keeps its 4.2.1 meaning.
    static let controlCenterOnlyPreferenceKey = "ControlCenterOnlyEnabled"

    /// How long an update-relaunch marker counts. Sparkle usually relaunches
    /// within seconds, but an installer that asks for an administrator
    /// password can wait on the person. A marker left by a relaunch that
    /// never happened must not silence a launch made much later.
    static let updateRelaunchMarkerLifetime: TimeInterval = 600

    /// Resolves the saved preferences. Control Center Only wins when it is
    /// on. Otherwise the legacy key decides, so someone who chose Hide Menu
    /// Bar Icon before this setting existed keeps it.
    static func mode(controlCenterOnlySaved: Bool, legacyHideMenuBarIconSaved: Bool) -> InterfaceVisibilityMode {
        if controlCenterOnlySaved { return .controlCenterOnly }
        if legacyHideMenuBarIconSaved { return .hideMenuBarIcon }
        return .menuBarIcon
    }

    /// The mode that actually applies. Either icon-hiding mode needs a
    /// usable Control Center control; without one the menu bar icon is the
    /// fallback. The saved preferences are left as they are.
    static func effectiveMode(_ mode: InterfaceVisibilityMode, controlCenterAvailable: Bool) -> InterfaceVisibilityMode {
        controlCenterAvailable ? mode : .menuBarIcon
    }

    static func isMenuBarIconHidden(mode: InterfaceVisibilityMode, controlCenterAvailable: Bool) -> Bool {
        effectiveMode(mode, controlCenterAvailable: controlCenterAvailable) != .menuBarIcon
    }

    /// The Dock icon the mode requires, or nil when Show Dock Icon decides.
    /// Hide Menu Bar Icon keeps the Dock icon on (the 4.2.1 lockout guard)
    /// without rewriting the saved Show Dock Icon choice. Control Center
    /// Only hides it and also leaves the saved choice alone, so either mode
    /// can be turned off and the person's choice comes back.
    static func dockIconOverride(mode: InterfaceVisibilityMode, controlCenterAvailable: Bool) -> Bool? {
        switch effectiveMode(mode, controlCenterAvailable: controlCenterAvailable) {
        case .menuBarIcon: return nil
        case .hideMenuBarIcon: return true
        case .controlCenterOnly: return false
        }
    }

    static func isDockIconShown(
        mode: InterfaceVisibilityMode,
        showDockIconPreference: Bool,
        controlCenterAvailable: Bool
    ) -> Bool {
        dockIconOverride(mode: mode, controlCenterAvailable: controlCenterAvailable) ?? showDockIconPreference
    }

    /// Combines the launch sources. Any silent source wins over `.direct`.
    static func launchReason(from signals: LaunchSignals) -> LaunchReason {
        if signals.launchedByControlCenter || signals.arguments.contains(controlCenterLaunchArgument) {
            return .controlCenter
        }
        if signals.launchedAsLoginItem { return .loginItem }
        if signals.relaunchedByUpdater { return .updateRelaunch }
        if !signals.launchIsDefault { return .sessionRestore }
        return .direct
    }

    /// Whether a marker saved at `markedAt` still describes this launch.
    static func isUpdateRelaunchMarkerFresh(markedAt: Date?, now: Date) -> Bool {
        guard let markedAt else { return false }
        let age = now.timeIntervalSince(markedAt)
        return age >= 0 && age <= updateRelaunchMarkerLifetime
    }

    /// Open Settings at launch when the app has no icon, the person opened
    /// it themselves, and no other launch window is already showing.
    static func shouldOpenSettingsAtLaunch(
        mode: InterfaceVisibilityMode,
        controlCenterAvailable: Bool,
        showDockIconPreference: Bool,
        launchReason: LaunchReason,
        welcomeVisible: Bool,
        licenseNoticeVisible: Bool
    ) -> Bool {
        let menuBarIconHidden = isMenuBarIconHidden(mode: mode, controlCenterAvailable: controlCenterAvailable)
        let dockIconShown = isDockIconShown(
            mode: mode,
            showDockIconPreference: showDockIconPreference,
            controlCenterAvailable: controlCenterAvailable
        )
        guard menuBarIconHidden, !dockIconShown else { return false }
        guard !launchReason.isSilent else { return false }
        return !welcomeVisible && !licenseNoticeVisible
    }
}

/// Settings text for each interface mode, kept here so the tests can check
/// that every mode explains itself.
enum InterfaceVisibilityCopy {
    static let controlCenterOnlyTitle = "Control Center Only"
    static let controlCenterOnlyDetail = "Use the Control Center toggle instead of the menu bar and Dock icons"
    static let addControlInstruction = "Add the Ping Protection control from Control Center → Edit Controls."
    static let returnToSettingsInstruction = "Open Ping Warden from Applications or Spotlight to return to Settings."

    static let confirmationTitle = "Use Control Center Only?"
    static let confirmationButton = "Use Control Center Only"
    static let confirmationMessage = "Ping Warden's menu bar and Dock icons will be hidden. \(addControlInstruction) To return to Settings, open Ping Warden from Applications or Spotlight."

    static let legacyStatusTitle = "Menu Bar Icon Hidden"
    static let legacyStatusDetail = "You chose Hide Menu Bar Icon in an earlier version. Ping Warden keeps its Dock icon so Settings stays one click away."
    static let showMenuBarIconButton = "Show Menu Bar Icon"

    /// The Automation footer for the effective mode, or nil for none.
    static func automationFooter(mode: InterfaceVisibilityMode) -> String? {
        switch mode {
        case .menuBarIcon:
            return nil
        case .hideMenuBarIcon:
            return "Turn on Control Center Only to hide the Dock icon too, or show the menu bar icon again."
        case .controlCenterOnly:
            return "\(addControlInstruction) Ping Warden also leaves the Dock. \(returnToSettingsInstruction)"
        }
    }

    /// The General footer under Show Dock Icon for the effective mode, or
    /// nil when the preference applies as saved.
    static func generalFooter(mode: InterfaceVisibilityMode) -> String? {
        switch mode {
        case .menuBarIcon:
            return nil
        case .hideMenuBarIcon:
            return "The menu bar icon is hidden, so Ping Warden keeps its Dock icon. Change this in Automation."
        case .controlCenterOnly:
            return "Control Center Only is on in Automation, so Ping Warden has no menu bar or Dock icon. Use the Control Center toggle. \(returnToSettingsInstruction)"
        }
    }
}
