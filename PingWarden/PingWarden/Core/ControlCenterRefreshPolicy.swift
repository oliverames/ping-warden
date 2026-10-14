import Foundation

/// Why the app asks Control Center to re-query the Ping Protection control.
///
/// WidgetKit can keep showing the last value it rendered after the app dies,
/// including a stale Protected (#101). Writes to the effective-state
/// preference already reload the control; these triggers cover recovery
/// points that may not write that preference at all, so the value provider
/// gets a fresh chance to compare the saved state with the running app and
/// the live awdl0 flags.
enum ControlCenterRefreshTrigger: String, CaseIterable, Sendable {
    /// A new app process. The previous one may have crashed while Protected.
    case appLaunch
    /// The helper answered again after a period of silence.
    case helperRecovered
    /// An explicit Repair finished, whatever its outcome.
    case repairFinished
    /// The Mac woke. The helper may have restarted while it slept.
    case systemWake
}

/// Coalesces control reloads so several recovery signals arriving together
/// (launch, reconnect, a reassert reply) produce one reload, not a storm.
///
/// The first request opens a short window and returns its length; requests
/// inside that window join it. `flush()` closes the window and reports what
/// it collected. Nothing here repeats on its own: no request, no reload.
struct ControlCenterRefreshCoalescer: Sendable {
    static let defaultWindow: TimeInterval = 0.5

    let window: TimeInterval
    private(set) var pendingTriggers: [ControlCenterRefreshTrigger] = []

    init(window: TimeInterval = ControlCenterRefreshCoalescer.defaultWindow) {
        self.window = max(0, window)
    }

    var hasPendingReload: Bool { !pendingTriggers.isEmpty }

    /// Record a request. Returns the delay after which the caller should call
    /// `flush()`, or nil when no new flush is needed: one is already pending,
    /// or the control cannot exist in this build (unsigned, wrong OS, no
    /// widget extension), so there is nothing to reload.
    mutating func request(
        _ trigger: ControlCenterRefreshTrigger,
        controlCenterAvailable: Bool
    ) -> TimeInterval? {
        guard controlCenterAvailable else { return nil }
        let startsWindow = pendingTriggers.isEmpty
        if !pendingTriggers.contains(trigger) {
            pendingTriggers.append(trigger)
        }
        return startsWindow ? window : nil
    }

    /// Close the window. Returns the triggers it collected, in arrival order;
    /// empty means there is nothing to reload.
    mutating func flush() -> [ControlCenterRefreshTrigger] {
        defer { pendingTriggers = [] }
        return pendingTriggers
    }
}
