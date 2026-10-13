// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// What the Advanced pane's helper test tells the person. The monitor's
/// health check returns one message for diagnostics exports as well, so the
/// alert picks a title and one recovery path from the outcome rather than
/// showing a diagnostic clause such as an XPC error code.
struct HelperTestReport: Equatable, Sendable {
    let title: String
    let message: String

    static let notSetUp = HelperTestReport(
        title: "Helper Not Set Up",
        message: "Click Finish Setup… in General, then allow Ping Warden in \(SystemSettingsCopy.loginItemsPaneName)."
    )

    static let notResponding = HelperTestReport(
        title: "Helper Not Responding",
        message: "Click Repair… below. If that fails, restart your Mac and click Repair… again."
    )

    static let awdlStillActive = HelperTestReport(
        title: "AWDL Is Still Active",
        message: "Ping Protection is on, but AWDL read as active. Run the test again. If it repeats, click Repair…"
    )

    /// - Parameters:
    ///   - helperRegistered: read after the check, so a registration that
    ///     disappeared while it ran reports as not set up.
    ///   - message: the health check's message. A healthy check already
    ///     carries the helper version and protection state in plain words.
    static func make(helperRegistered: Bool, isHealthy: Bool, message: String) -> HelperTestReport {
        if isHealthy {
            return HelperTestReport(title: "Helper Is Working", message: message)
        }
        if !helperRegistered {
            return .notSetUp
        }
        // The helper answered, but awdl0 reads up while protection is on.
        // Every other failure means the helper never answered.
        if message == HelperRecovery.interfaceHealth(protectionRequested: true, interfaceUp: true).summary {
            return .awdlStillActive
        }
        return .notResponding
    }
}

/// Feedback around Repair. The menu, the Dashboard, and Settings share it,
/// so every entry point says the same thing before and after.
enum RepairResultCopy {
    static let confirmationTitle = "Repair Helper Connection?"

    /// Repair checks the helper first and leaves an answering helper alone.
    /// A silent one is unregistered and registered again. That is when
    /// macOS can announce it and, if the approval did not survive, ask for
    /// it again.
    static func confirmationMessage(osMajorVersion: Int) -> String {
        let pane = SystemSettingsCopy.loginItemsPaneName(osMajorVersion: osMajorVersion)
        return """
        1. Ping Warden checks whether the helper answers. If it does, nothing else changes.
        2. If it does not answer, Ping Warden removes the helper and registers it again. macOS may show a Background Items Added notification.
        3. If Ping Warden is off in \(pane), turn it on under Allow in the Background. macOS may ask for your password or Touch ID.

        Your protection preference, settings, and session history stay as they are.
        """
    }

    static let confirmationMessage = confirmationMessage(osMajorVersion: SystemSettingsCopy.currentMajorVersion)
    static let accessibilityHint = "Checks the helper connection and offers to register it again without changing your protection preference"
    static let restoringFailureMessage = "The helper is responding again, but Ping Warden could not restore protection. Your saved protection preference has not changed."
    static let successTitle = "Helper Is Responding"

    static func successMessage(protectionOn: Bool) -> String {
        protectionOn ? SetupGuideCopy.protectionOnConfirmation : "Ping Protection is off."
    }

    static let failureTitle = "Helper Still Not Responding"

    static func failureMessage(osMajorVersion: Int) -> String {
        """
        Ping Warden could not get a response from its helper.
        1. Make sure Ping Warden is turned on in \(SystemSettingsCopy.loginItemsPath(osMajorVersion: osMajorVersion)).
        2. Restart your Mac.
        3. Try Repair again.
        If it still fails, open the Troubleshooting Guide.
        """
    }

    static let failureMessage = failureMessage(osMajorVersion: SystemSettingsCopy.currentMajorVersion)
}

/// What the welcome window and Finish Setup… say before, during, and after
/// helper approval. Each step matches `PingWardenMonitor.registerHelper`: a
/// fresh registration gets macOS's own notification, Ping Warden opens Login
/// Items itself when approval is still pending 10 seconds later (at once for
/// a registration that was already waiting), and it stops waiting after one
/// minute.
enum SetupGuideCopy {
    static let stepsTitle = "What happens next"

    static func steps(osMajorVersion: Int) -> [String] {
        [
            "macOS shows a Background Items Added notification.",
            "Open \(SystemSettingsCopy.loginItemsPath(osMajorVersion: osMajorVersion)). If approval is still pending after a few seconds, Ping Warden opens it for you.",
            "Under Allow in the Background, turn on Ping Warden.",
            "macOS may ask for your password or Touch ID.",
            "Come back here. Setup finishes on its own."
        ]
    }

    static let steps = steps(osMajorVersion: SystemSettingsCopy.currentMajorVersion)

    static let timeoutHint = "If approval takes longer than a minute, click Try Again."

    static let waitingTitle = "Waiting for approval"

    static func waitingDetail(osMajorVersion: Int) -> String {
        "macOS shows a Background Items Added notification. In \(SystemSettingsCopy.loginItemsPath(osMajorVersion: osMajorVersion)), turn on Ping Warden under Allow in the Background. macOS may ask for your password. Then come back here."
    }

    static let waitingDetail = waitingDetail(osMajorVersion: SystemSettingsCopy.currentMajorVersion)

    static let failedTitle = "Setup did not finish"

    static func failedFallback(osMajorVersion: Int) -> String {
        "macOS did not finish approving the helper. Check \(SystemSettingsCopy.loginItemsPaneName(osMajorVersion: osMajorVersion)), then click Try Again."
    }

    static let failedFallback = failedFallback(osMajorVersion: SystemSettingsCopy.currentMajorVersion)

    /// The menu bar icon and the Control Center control both switch to
    /// `antenna.radiowaves.left.and.right.slash` while protection is on.
    static let protectionOnConfirmation = "Ping Protection is on. The Ping Warden icon shows a crossed-out antenna while it is active."

    static let completeProtectionOn = "Setup complete. \(protectionOnConfirmation)"
    static let completeLicenseNeeded = "Helper ready. Enter a license to turn on Ping Protection."
    static let completeProtectionOff = "Helper ready. Ping Protection is off."

    /// Checked against PingWardenHelper: it opens an AF_ROUTE socket to
    /// watch interface changes and an AF_INET socket used only for ioctl
    /// on awdl0. It never connects, sends, or captures packets.
    static let helperCaption = "The helper only turns the AirDrop interface (awdl0) off and on. It never reads your traffic or connects to the internet."
    static let helperLinkTitle = "What does the helper do?"

    /// Alert title for a Finish Setup… that did not get a helper reply.
    static let finishSetupFailedTitle = "Setup Did Not Finish"
}

/// Pages on pingwarden.app that error messages point to. Each anchor is a
/// heading id in Site/public/docs.
enum HelpLinks {
    static let troubleshootingTitle = "Troubleshooting Guide"
    static let messages = URL(string: "https://pingwarden.app/docs/troubleshooting#messages-you-might-see")!
    static let helperStillNotResponding = URL(string: "https://pingwarden.app/docs/troubleshooting#helper-still-not-responding")!
    static let setupDidNotFinish = URL(string: "https://pingwarden.app/docs/troubleshooting#setup-did-not-finish")!
    static let maintenanceCouldNotFinish = URL(string: "https://pingwarden.app/docs/troubleshooting#maintenance-could-not-finish")!
    static let whatTheHelperDoes = URL(string: "https://pingwarden.app/docs/setup#what-the-helper-is-and-why-it-needs-approval")!
}

/// Prepare to Remove copy for an Off command that did not finish.
enum RemovalCopy {
    /// Only when the helper never answered the Off command.
    static let helperSilent = "The helper is not responding, so Ping Warden could not turn off protection safely. Click Repair… under Maintenance, then try again. If Repair fails, see the Troubleshooting Guide."
    static let couldNotTurnOff = "Ping Protection could not be turned off, so no settings were erased. Quit Ping Warden to restore wireless sharing, then try again."
}

/// Directions for a copy of Ping Warden that Gatekeeper could not verify.
/// macOS 15 removed the Control-click Open bypass; approval moved to the
/// Open Anyway button in Privacy & Security, which macOS 13 and 14 also have.
enum GatekeeperCopy {
    static let title = "macOS Could Not Verify Ping Warden"

    static func message(osMajorVersion: Int) -> String {
        let intro = "Download the current signed and notarized release from the official GitHub Releases page."
        let openAnyway = "open System Settings → Privacy & Security, scroll to Security, and click Open Anyway for Ping Warden."
        let ownBuild: String
        if osMajorVersion >= 15 {
            ownBuild = "If you built this copy yourself, try to open it once, then \(openAnyway)"
        } else {
            ownBuild = "If you built this copy yourself, Control-click it in Finder and choose Open. You can also try to open it once, then \(openAnyway)"
        }
        return "\(intro)\n\n\(ownBuild) Ping Warden will never ask you to remove quarantine attributes in Terminal."
    }
}
