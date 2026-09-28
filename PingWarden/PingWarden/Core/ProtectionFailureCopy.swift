// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// User-facing copy for protection commands that failed. Quitting Ping
/// Warden restores wireless sharing only when the helper is running and
/// notices the app's connection close, so that advice is reserved for a
/// helper that answered. A helper that never answered points to Repair.
enum ProtectionFailureCopy {
    enum Action: Equatable, Sendable {
        case turnOn
        case turnOff
        case pause
        case startSession
    }

    static let helperNotResponding = "Ping Warden's helper is not responding. Open Settings → Advanced and click Repair."

    static let repairHint = "Open Settings → Advanced and click Repair."

    static func message(for action: Action, failure: HelperCommandFailure?) -> String {
        let helperSilent = failure?.helperDidNotAnswer ?? false
        switch (action, helperSilent) {
        case (.turnOn, true):
            return "Ping Protection could not turn on because the helper is not responding. \(repairHint)"
        case (.turnOn, false):
            return "Ping Protection could not turn on. \(repairHint)"
        case (.turnOff, true):
            return "Ping Protection could not turn off because the helper is not responding. \(repairHint) If wireless sharing stays unavailable, restart your Mac."
        case (.turnOff, false):
            return "Ping Protection could not turn off. Quit Ping Warden to restore wireless sharing, then try again."
        case (.pause, true):
            return "Ping Protection could not pause because the helper is not responding. \(repairHint) If wireless sharing stays unavailable, restart your Mac."
        case (.pause, false):
            return "Ping Protection could not pause. Quit Ping Warden to restore wireless sharing, then try again."
        case (.startSession, true):
            return "Ping Protection could not turn on because the helper is not responding, so the latency session did not start. \(repairHint)"
        case (.startSession, false):
            return "Ping Protection could not turn on, so the latency session did not start."
        }
    }

    /// Reported without an alert when the monitor's bounded reconnect gives
    /// up. The app keeps running, so the old advice to restart it was wrong.
    static let lostHelperConnection = "Lost connection to the helper, so Ping Protection turned off. \(repairHint)"

    /// Reported without an alert when a reconnected helper refuses to
    /// reapply protection.
    static let restoreAfterReconnectFailed = "Ping Protection could not be restored after the helper restarted. \(repairHint)"

    /// Shown when a saved intent to protect waits on a helper that is not
    /// approved yet. Launch never opens Login Items on its own.
    static let setupIncomplete = "Ping Protection is waiting for setup. Choose Finish Setup to approve the helper in \(SystemSettingsCopy.loginItemsPaneName)."
}

/// Names of System Settings panes that the app points people to. macOS 15
/// renamed Login Items to Login Items & Extensions, so directions written
/// for one release are wrong on the other. Kept Foundation-only because the
/// monitor and coordinator test harnesses compile this file directly.
enum SystemSettingsCopy {
    static func loginItemsPaneName(osMajorVersion: Int) -> String {
        osMajorVersion >= 15 ? "Login Items & Extensions" : "Login Items"
    }

    static func loginItemsPath(osMajorVersion: Int) -> String {
        "System Settings → General → \(loginItemsPaneName(osMajorVersion: osMajorVersion))"
    }

    static let loginItemsPaneName = loginItemsPaneName(osMajorVersion: currentMajorVersion)
    static let loginItemsPath = loginItemsPath(osMajorVersion: currentMajorVersion)

    private static var currentMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }
}

/// License copy shared by the protection coordinator, the menu alert, and
/// Settings. Gumroad answers `success: false` for a mistyped key and for a
/// refunded or disabled one alike, so the rejection copy names neither.
enum LicenseCopy {
    /// Matches `LicenseManager.donationConversionEmail`, which this
    /// Foundation-only file cannot reach.
    static let supportEmail = "oliver@ames.consulting"

    static let required = "Ping Protection needs a one-time $15 license. If you already bought one, enter the key in Settings → License. Donated before version 4? Email \(supportEmail)."

    static let transitionEnded = "The transition period has ended. \(required)"

    static func required(transitionEnded ended: Bool) -> String {
        ended ? transitionEnded : required
    }

    static func stayedOffAtLaunch(transitionEnded ended: Bool) -> String {
        "Ping Protection stayed off. \(required(transitionEnded: ended))"
    }

    static let revoked = "The license for Ping Protection is no longer valid, so protection turned off. Enter a valid key in Settings → License. If you think this is a mistake, email \(supportEmail)."

    static let keyNotAccepted = "Gumroad did not accept this key. Check that you copied the whole key from your Gumroad receipt, then try again. If it still fails, email \(supportEmail)."
}
