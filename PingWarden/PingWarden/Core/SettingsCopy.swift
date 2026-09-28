// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// What the Advanced pane's helper test tells the person. The monitor's
/// health check returns one message for diagnostics exports as well, so the
/// alert picks a title and one recovery path from the outcome rather than
/// showing a diagnostic clause such as an XPC error code.
struct HelperTestReport: Equatable {
    let title: String
    let message: String

    static let notSetUp = HelperTestReport(
        title: "Helper Not Set Up",
        message: "Click Finish Setup… in General, then allow Ping Warden in \(SystemSettingsCopy.loginItemsPaneName)."
    )

    static let notResponding = HelperTestReport(
        title: "Helper Not Responding",
        message: "Click Repair below. If that fails, restart your Mac and click Repair again."
    )

    static let awdlStillActive = HelperTestReport(
        title: "AWDL Is Still Active",
        message: "Ping Protection is on, but AWDL is still active. Click Repair below."
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

/// Feedback after Repair in the Advanced pane.
enum RepairResultCopy {
    static let successTitle = "Helper Is Responding"

    static func successMessage(protectionOn: Bool) -> String {
        protectionOn ? "Ping Protection is on." : "Ping Protection is off."
    }

    static let failureTitle = "Helper Still Not Responding"

    static let failureMessage = "Ping Warden could not get a response from its helper. Make sure Ping Warden is allowed in \(SystemSettingsCopy.loginItemsPath), restart your Mac, then click Repair again."
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
