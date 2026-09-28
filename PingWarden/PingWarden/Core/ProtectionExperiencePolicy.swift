import Foundation

enum ProtectionSessionPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case starting
    case active
    case stopping
}

enum ProtectionExperiencePolicy {
    struct State: Equatable, Sendable {
        var helperAvailable: Bool
        var persistentProtectionEnabled: Bool
        var effectiveProtectionEnabled: Bool
        var sessionPhase: ProtectionSessionPhase
        var sessionTrigger: ProtectedSessionTrigger?
        var pauseUntil: Date?
        var licenseAllowsProtection: Bool
        /// The monitor holds a protection request, confirmed or reconnecting.
        var protectionRequested: Bool
        /// A protection command is waiting on the helper's reply.
        var commandInFlight: Bool
        /// False once the helper has gone unanswered, until it replies again.
        var helperResponding: Bool

        init(
            helperAvailable: Bool,
            persistentProtectionEnabled: Bool,
            effectiveProtectionEnabled: Bool,
            sessionPhase: ProtectionSessionPhase,
            sessionTrigger: ProtectedSessionTrigger?,
            pauseUntil: Date?,
            licenseAllowsProtection: Bool = true,
            protectionRequested: Bool = false,
            commandInFlight: Bool = false,
            helperResponding: Bool = true
        ) {
            self.helperAvailable = helperAvailable
            self.persistentProtectionEnabled = persistentProtectionEnabled
            self.effectiveProtectionEnabled = effectiveProtectionEnabled
            self.sessionPhase = sessionPhase
            self.sessionTrigger = sessionTrigger
            self.pauseUntil = pauseUntil
            self.licenseAllowsProtection = licenseAllowsProtection
            self.protectionRequested = protectionRequested
            self.commandInFlight = commandInFlight
            self.helperResponding = helperResponding
        }
    }

    /// What the one protection toggle does. The menu item, the Dashboard
    /// button, and their titles all derive from this, so a control can
    /// never be labeled "Turn Off" while it turns protection on.
    enum ToggleAction: Equatable, Sendable {
        case finishSetup
        case turnOn
        case turnOff

        var menuTitle: String {
            switch self {
            case .finishSetup: return "Finish Setup..."
            case .turnOn: return "Turn On Ping Protection"
            case .turnOff: return "Turn Off Ping Protection"
            }
        }

        var buttonTitle: String {
            switch self {
            case .finishSetup: return "Finish Setup..."
            case .turnOn: return "Turn On"
            case .turnOff: return "Turn Off"
            }
        }
    }

    struct MenuPresentation: Equatable, Sendable {
        let protectionTitle: String
        let protectionActionEnabled: Bool
        let pauseTitle: String?
        let pauseActionEnabled: Bool
        let statusTitle: String
    }

    static func activePauseUntil(in state: State, now: Date) -> Date? {
        guard let pauseUntil = state.pauseUntil, pauseUntil > now else {
            return nil
        }
        return pauseUntil
    }

    static func isPaused(_ state: State, now: Date) -> Bool {
        activePauseUntil(in: state, now: now) != nil
    }

    static func sessionRequiresProtection(_ phase: ProtectionSessionPhase) -> Bool {
        switch phase {
        case .starting, .active, .stopping:
            return true
        case .idle:
            return false
        }
    }

    static func shouldEnableProtection(for state: State, now: Date) -> Bool {
        guard state.helperAvailable, state.licenseAllowsProtection, !isPaused(state, now: now) else {
            return false
        }
        return state.persistentProtectionEnabled || sessionRequiresProtection(state.sessionPhase)
    }

    /// What launch does with a saved intent before the normal reconcile.
    enum LaunchIntentAction: Equatable, Sendable {
        /// Nothing beyond the reconcile, which runs once the helper is known.
        case none
        /// The entitlement is gone, so the saved intent is cleared.
        case clearIntentForLicense
        /// No approved helper yet. The intent waits for Finish Setup;
        /// enabling would open Login Items with no action from the person.
        case waitForSetup
    }

    static func launchIntentAction(
        persistentProtectionEnabled: Bool,
        licenseAllowsProtection: Bool,
        helperRegistered: Bool
    ) -> LaunchIntentAction {
        guard persistentProtectionEnabled else { return .none }
        guard licenseAllowsProtection else { return .clearIntentForLicense }
        return helperRegistered ? .none : .waitForSetup
    }

    /// Protection is on, being restored, or wanted: the toggle turns it off.
    /// Otherwise, including during a pause, the toggle turns it on.
    static func toggleAction(for state: State, now: Date) -> ToggleAction {
        guard state.helperAvailable else { return .finishSetup }
        let protectionOnOrPending = state.effectiveProtectionEnabled
            || state.protectionRequested
            || shouldEnableProtection(for: state, now: now)
        return protectionOnOrPending ? .turnOff : .turnOn
    }

    static func presentation(for state: State, now: Date) -> MenuPresentation {
        let paused = isPaused(state, now: now)
        let desiredProtection = shouldEnableProtection(for: state, now: now)
        let protectionOnOrPending = state.effectiveProtectionEnabled || desiredProtection
        let isTransitioningSession = state.sessionPhase == .starting
            || state.sessionPhase == .stopping

        let protectionTitle = toggleAction(for: state, now: now).menuTitle

        let pauseTitle: String?
        if paused {
            pauseTitle = "Resume Ping Protection"
        } else if protectionOnOrPending && !isTransitioningSession {
            pauseTitle = "Pause for 10 Minutes"
        } else {
            pauseTitle = nil
        }

        return MenuPresentation(
            protectionTitle: protectionTitle,
            protectionActionEnabled: !isTransitioningSession,
            pauseTitle: state.helperAvailable ? pauseTitle : nil,
            pauseActionEnabled: state.helperAvailable
                && pauseTitle != nil
                && !isTransitioningSession,
            statusTitle: statusTitle(
                for: state,
                paused: paused,
                desiredProtection: desiredProtection
            )
        )
    }

    private static func statusTitle(
        for state: State,
        paused: Bool,
        desiredProtection: Bool
    ) -> String {
        guard state.helperAvailable else {
            return "Status: Not Set Up"
        }
        if paused {
            return "Status: Paused"
        }

        switch state.sessionPhase {
        case .starting:
            return "Status: Starting Latency Session"
        case .stopping:
            return "Status: Ending Latency Session"
        case .active where state.effectiveProtectionEnabled:
            if state.sessionTrigger == .gameMode {
                return "Status: Protected, Game Mode Session Active"
            }
            return "Status: Protected, Latency Session Active"
        case .active:
            return "Status: Restoring Protection"
        case .idle:
            break
        }

        // "Turning On" and "Turning Off" describe a command awaiting the
        // helper. Without one, a mismatch is reported as it stands so a
        // silent helper cannot leave the menu promising progress forever.
        if desiredProtection && !state.effectiveProtectionEnabled {
            if state.commandInFlight {
                return "Status: Turning On Protection"
            }
            if state.protectionRequested {
                return "Status: Reconnecting to Helper"
            }
            return state.helperResponding
                ? "Status: Not Protected"
                : "Status: Not Protected, Helper Not Responding"
        }
        if !desiredProtection && state.effectiveProtectionEnabled && state.commandInFlight {
            return "Status: Turning Off Protection"
        }
        return state.effectiveProtectionEnabled
            ? "Status: Protected"
            : "Status: Not Protected"
    }
}
