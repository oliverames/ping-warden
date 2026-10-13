// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// Keeps the optional introduction separate from privileged-helper setup.
/// Explicit setup actions can still present the welcome after this marker is set.
public struct WelcomePresentationState {
    private let defaults: UserDefaults
    private let presentedKey = "WelcomeHasBeenPresented"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func shouldPresentAutomatically(helperIsRegistered: Bool) -> Bool {
        !helperIsRegistered && !defaults.bool(forKey: presentedKey)
    }

    public func markPresented() {
        defaults.set(true, forKey: presentedKey)
    }
}

/// Decisions for the welcome window's setup area, kept apart from the view
/// so they can be tested without AppKit.
enum WelcomeSetupPolicy {
    enum PrimaryAction: Equatable {
        /// Helper setup leads, because the person can turn protection on.
        case setUpProtection
        /// The free dashboard leads; setup stays one click away.
        case openDashboard
    }

    /// Without a license or an active transition, setup alone cannot turn
    /// protection on, so the first run leads with what works for free.
    static func primaryAction(canEnableProtection: Bool) -> PrimaryAction {
        canEnableProtection ? .setUpProtection : .openDashboard
    }

    enum Progress: Equatable {
        /// Repair is rebuilding or confirming an approved helper.
        case checkingHelper
        /// A new registration waits for approval in System Settings.
        case waitingForApproval
    }

    /// An approved helper needs no approval, so saying the app waits for
    /// one would send the person to System Settings for nothing.
    static func progress(helperRegistered: Bool) -> Progress {
        helperRegistered ? .checkingHelper : .waitingForApproval
    }
}
