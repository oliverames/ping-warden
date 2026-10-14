// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// When to offer Repair on the app's own initiative because the helper is
/// not working while Ping Protection needs it.
///
/// The passive surfaces (the menu's status line and Repair… item, the
/// Dashboard's Repair row) are always there. This adds one active offer per
/// failure episode, after a short wait so a blip right after launch or wake
/// passes without a word. The offer only asks: Repair starts, and macOS is
/// asked for anything, only after the person clicks.
///
/// Nobody is offered Repair while protection is not needed, so an
/// unlicensed person on the free dashboard, or anyone who turned
/// protection off, is never asked about the helper.
enum HelperRepairOffer {
    /// What is wrong with the helper.
    enum Problem: String, Equatable, Sendable {
        /// The helper is registered and approved, but a request went
        /// unanswered.
        case notResponding
        /// Protection is meant to be on, but the helper is not approved
        /// (for example it was turned off in Login Items).
        case notApproved
    }

    /// The offer's words. Repair checks first and asks before macOS shows
    /// anything, so the offer says so.
    enum Copy {
        static let repairButton = "Repair…"
        static let notNowButton = "Not Now"

        static func title(for problem: Problem) -> String {
            switch problem {
            case .notResponding: return "Ping Warden's Helper Isn't Responding"
            case .notApproved: return "Ping Warden's Helper Needs Approval"
            }
        }

        static func message(for problem: Problem) -> String {
            switch problem {
            case .notResponding:
                return "Ping Protection needs the helper, but it hasn't answered, so protection may not be working. Repair checks the helper first and only asks you to approve it again if it has to. Your protection setting stays as it is."
            case .notApproved:
                return "Ping Protection is set to turn on, but the helper isn't allowed to run, for example because it was turned off in System Settings. Repair walks you through approving it again. Nothing changes until you click Approve Helper."
            }
        }
    }

    /// How long a problem must last before it is offered. Launch and wake
    /// reconnect within a few seconds, and an automatic retry follows a
    /// helper that answers again.
    static let debounce: TimeInterval = 10

    /// The live facts the decision needs.
    struct State: Equatable, Sendable {
        /// The helper's problem right now, if any.
        let problem: Problem?
        /// A license or the transition allows protection.
        let licenseAllowsProtection: Bool
        /// Protection is on, saved as on, being turned on, or held by a
        /// latency or Game Mode session. A pause counts: it ends on its own
        /// and then needs the helper.
        let protectionNeeded: Bool
        /// A Repair, setup, protection change, or quit is in progress; it
        /// owns the outcome for now.
        let busy: Bool
    }

    enum Decision: Equatable, Sendable {
        /// Nothing to offer.
        case none
        /// Ask again after this many seconds.
        case wait(TimeInterval)
        /// Offer Repair for this problem now.
        case offer(Problem)
    }

    /// One failure episode: from the first sign of a problem until the
    /// helper works again (or nothing needs it). At most one offer each.
    struct Episode: Equatable, Sendable {
        var problem: Problem
        let since: Date
        var offered: Bool
    }

    /// Tracks the current episode and decides. Kept by the coordinator.
    struct Tracker: Equatable, Sendable {
        private(set) var episode: Episode?

        init() {}

        /// Update with the live state and decide. A state without a problem
        /// ends the episode, so the next failure is a new one.
        mutating func evaluate(
            _ state: State,
            now: Date,
            debounce: TimeInterval = HelperRepairOffer.debounce
        ) -> Decision {
            guard let problem = state.problem else {
                episode = nil
                return .none
            }
            if episode == nil {
                episode = Episode(problem: problem, since: now, offered: false)
            } else {
                // A helper that went from unapproved to silent (or back) is
                // the same episode: it is not offered twice.
                episode?.problem = problem
            }
            guard let episode, !episode.offered,
                  state.licenseAllowsProtection, state.protectionNeeded else {
                return .none
            }
            // Whatever is in progress may settle it; look again later.
            if state.busy { return .wait(debounce) }
            let elapsed = now.timeIntervalSince(episode.since)
            if elapsed < debounce {
                return .wait(debounce - elapsed)
            }
            return .offer(problem)
        }

        /// The person has been offered Repair (or started it, or was offered
        /// it in response to their own toggle): no further offer this episode.
        /// `problem` starts the episode when none is open yet, so a Repair
        /// that just failed is not followed by an automatic offer; nil
        /// ends the episode.
        mutating func markOffered(problem: Problem?, now: Date) {
            guard let problem else {
                episode = nil
                return
            }
            if episode == nil {
                episode = Episode(problem: problem, since: now, offered: true)
            } else {
                episode?.problem = problem
                episode?.offered = true
            }
        }
    }
}
