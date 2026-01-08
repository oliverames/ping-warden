import Foundation

/// Manages shared state between app and widget using App Groups
class AWDLPreferences {
    static let shared = AWDLPreferences()

    private let appGroupID = "group.com.awdlcontrol.app"
    private let monitoringEnabledKey = "AWDLMonitoringEnabled"
    private let lastStateKey = "AWDLLastState"
    private let controlCenterEnabledKey = "ControlCenterWidgetEnabled"

    private var defaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    /// Whether continuous AWDL monitoring is enabled
    var isMonitoringEnabled: Bool {
        get {
            return defaults?.bool(forKey: monitoringEnabledKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: monitoringEnabledKey)

            // Post notification for app to respond
            NotificationCenter.default.post(name: .awdlMonitoringStateChanged, object: nil)
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
