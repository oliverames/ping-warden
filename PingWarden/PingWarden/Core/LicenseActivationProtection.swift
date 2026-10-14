// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// Whether a license the person just activated turns Ping Protection on,
/// and, when it does not, why.
///
/// Asked only after an explicit, successful Verify: in Settings → License,
/// in the setup window's license step, or at the end of the approval or
/// Repair that one of those started. Launch-time and periodic license
/// re-verification never ask it, so a background check can never turn
/// protection on.
///
/// Protection is turned on through the coordinator's
/// `setPersistentProtection(true)`, the path the person's own toggle uses,
/// so the saved choice, the menu, the Dashboard and Control Center follow
/// as they always do.
enum LicenseActivationProtection: Equatable, Sendable {
    /// Turn protection on and save that choice.
    case turnOn
    /// No license (or transition) allows protection. Nothing changes.
    case notLicensed
    /// Protection is already on and saved as on.
    case alreadyOn
    /// A ten-minute pause is running. It is kept: turning protection on
    /// would end it early, which the person did not ask for. When it ends,
    /// protection resumes from the saved choice, which was on when the
    /// pause began.
    case pauseActive
    /// A latency or Game Mode session holds protection on for now. It is
    /// left alone, and the saved choice still decides what follows it.
    case sessionActive
    /// A protection change, Repair, or quit is in progress. That change
    /// owns the outcome; starting another would supersede it.
    case changeInFlight

    struct State: Equatable, Sendable {
        let canEnableProtection: Bool
        /// The helper reports protection as on.
        let protectionOn: Bool
        /// The saved protection choice.
        let savedChoiceOn: Bool
        let pauseActive: Bool
        /// A latency or Game Mode session is starting, running, or stopping.
        let sessionActive: Bool
        let changeInFlight: Bool
    }

    static func decide(_ state: State) -> LicenseActivationProtection {
        guard state.canEnableProtection else { return .notLicensed }
        if state.changeInFlight { return .changeInFlight }
        if state.sessionActive { return .sessionActive }
        if state.pauseActive { return .pauseActive }
        if state.protectionOn, state.savedChoiceOn { return .alreadyOn }
        return .turnOn
    }
}
