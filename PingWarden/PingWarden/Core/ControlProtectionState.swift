import Foundation

/// Conservative, read-only display policy for one Control Center value request.
/// Saved user intent is deliberately not an input: an enabled preference does
/// not establish that protection is currently being applied.
enum ControlProtectionState {
    enum InterfaceState: CaseIterable, Sendable {
        case down
        case up
        case unknown
    }

    static func isProtected(
        usesSharedPreferences: Bool,
        effectiveMonitoringEnabled: Bool,
        containingAppIsRunning: Bool,
        interfaceState: InterfaceState
    ) -> Bool {
        usesSharedPreferences && effectiveMonitoringEnabled &&
            containingAppIsRunning && interfaceState == .down
    }

    /// Another installed copy with the same identifier is not the containing
    /// app. Missing process metadata cannot establish ownership either.
    static func matchesContainingApp(
        expectedBundleIdentifier: String,
        expectedBundleURL: URL,
        runningBundleIdentifier: String?,
        runningBundleURL: URL?,
        isTerminated: Bool
    ) -> Bool {
        !isTerminated && runningBundleIdentifier == expectedBundleIdentifier &&
            runningBundleURL?.standardizedFileURL == expectedBundleURL.standardizedFileURL
    }
}
