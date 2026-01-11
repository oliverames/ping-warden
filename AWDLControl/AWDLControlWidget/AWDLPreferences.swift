//
//  AWDLPreferences.swift
//  AWDLControlWidget
//
//  Manages shared state between app and widget using App Groups.
//
//  Copyright (c) 2025 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import os.log

private let log = Logger(subsystem: "com.awdlcontrol.app", category: "WidgetPreferences")

/// Manages shared state between app and widget using App Groups
/// Note: This file should be kept in sync with AWDLControl/AWDLPreferences.swift
/// The widget only uses isMonitoringEnabled and lastKnownState, but all properties
/// are included for consistency and to ensure key names match.
class AWDLPreferences {
    static let shared = AWDLPreferences()

    private let appGroupID = "group.com.awdlcontrol.app"
    private let monitoringEnabledKey = "AWDLMonitoringEnabled"
    private let lastStateKey = "AWDLLastState"
    private let controlCenterEnabledKey = "ControlCenterWidgetEnabled"
    private let gameModeAutoDetectKey = "GameModeAutoDetect"
    private let showDockIconKey = "ShowDockIcon"

    private lazy var defaults: UserDefaults? = {
        guard let suite = UserDefaults(suiteName: appGroupID) else {
            // Fallback to standard defaults if app group fails
            // This matches the main app's behavior for consistency
            log.error("Failed to create App Group suite '\(self.appGroupID)', using standard defaults")
            return UserDefaults.standard
        }
        log.debug("Successfully connected to App Group suite")
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
            defaults?.synchronize()

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

    /// Whether Control Center widget mode is enabled (hides menu bar icon)
    var controlCenterWidgetEnabled: Bool {
        get {
            return defaults?.bool(forKey: controlCenterEnabledKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: controlCenterEnabledKey)
            // Note: Widget doesn't post this notification as it's only used by main app
        }
    }

    /// Whether to auto-enable AWDL blocking when Game Mode is active
    var gameModeAutoDetect: Bool {
        get {
            return defaults?.bool(forKey: gameModeAutoDetectKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: gameModeAutoDetectKey)
            // Note: Widget doesn't post this notification as it's only used by main app
        }
    }

    /// Whether to show the app icon in the Dock
    var showDockIcon: Bool {
        get {
            return defaults?.bool(forKey: showDockIconKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: showDockIconKey)
            // Note: Widget doesn't post this notification as it's only used by main app
        }
    }
}

extension Notification.Name {
    // Use a namespaced notification name to avoid collisions with other apps
    static let awdlMonitoringStateChanged = Notification.Name("com.awdlcontrol.notification.MonitoringStateChanged")
    // These are defined in the main app but included here for reference:
    // static let controlCenterModeChanged = Notification.Name("com.awdlcontrol.notification.ControlCenterModeChanged")
    // static let gameModeAutoDetectChanged = Notification.Name("com.awdlcontrol.notification.GameModeAutoDetectChanged")
    // static let dockIconVisibilityChanged = Notification.Name("com.awdlcontrol.notification.DockIconVisibilityChanged")
}
