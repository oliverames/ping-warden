import Foundation

/// Manages shared state between app and widget using App Groups
class AWDLPreferences {
    static let shared = AWDLPreferences()

    private let appGroupID = "group.com.awdlcontrol.app"
    private let monitoringEnabledKey = "AWDLMonitoringEnabled"
    private let lastStateKey = "AWDLLastState"
    private let controlCenterEnabledKey = "ControlCenterWidgetEnabled"

    private lazy var defaults: UserDefaults? = {
        guard let suite = UserDefaults(suiteName: appGroupID) else {
            // Fallback to standard defaults if app group fails
            // This matches the main app's behavior for consistency
            return UserDefaults.standard
        }
        return suite
    }()

    private init() {}

    /// Whether continuous AWDL monitoring is enabled
    var isMonitoringEnabled: Bool {
        get {
            return defaults?.bool(forKey: monitoringEnabledKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: monitoringEnabledKey)

            // Use distributed notification for cross-process communication
            // NotificationCenter.default only works within the same process
            DistributedNotificationCenter.default().postNotificationName(
                .awdlMonitoringStateChanged,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    /// Last known AWDL state (for widget display)
    var lastKnownState: String {
        get {
            return defaults?.string(forKey: lastStateKey) ?? "unknown"
        }
        set {
            defaults?.set(newValue, forKey: lastStateKey)
        }
    }

    /// Whether Control Center widget mode is enabled
    var controlCenterWidgetEnabled: Bool {
        get {
            return defaults?.bool(forKey: controlCenterEnabledKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: controlCenterEnabledKey)
        }
    }
}

extension Notification.Name {
    static let awdlMonitoringStateChanged = Notification.Name("AWDLMonitoringStateChanged")
}
