//
//  AWDLPreferences.swift
//  AWDLControl
//
//  Manages shared state between app and widget using App Groups.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import os.log

private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "Preferences")

/// Manages shared state between app and widget using App Groups
class AWDLPreferences {
    static let shared = AWDLPreferences()

    private let appGroupID = "group.com.amesvt.pingwarden"
    private let monitoringEnabledKey = "AWDLMonitoringEnabled" // User intent
    private let effectiveMonitoringEnabledKey = "AWDLEffectiveMonitoringEnabled" // Runtime state
    private let lastStateKey = "AWDLLastState"
    private let controlCenterEnabledKey = "ControlCenterWidgetEnabled"
    private let gameModeAutoDetectKey = "GameModeAutoDetect"
    private let showDockIconKey = "ShowDockIcon"

    private lazy var defaults: UserDefaults? = {
        // Use standard UserDefaults if App Groups aren't available
        guard let suite = UserDefaults(suiteName: appGroupID) else {
            log.error("Failed to create App Group suite '\(self.appGroupID)', using standard defaults")
            return UserDefaults.standard
        }
        log.debug("Successfully connected to App Group suite")
        return suite
    }()

    private init() {}

    /// User intent for whether AWDL monitoring should be enabled.
    /// This is shared with the widget.
    var isMonitoringEnabled: Bool {
        get {
            return defaults?.bool(forKey: monitoringEnabledKey) ?? false
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.monitoringEnabledKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: monitoringEnabledKey)
            // Note: synchronize() is deprecated since macOS 10.14 - the system
            // automatically synchronizes UserDefaults at appropriate times
            // Use distributed notification for cross-process communication with widget
            DistributedNotificationCenter.default().postNotificationName(
                .awdlMonitoringStateChanged,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    /// Effective runtime state of monitoring as reported by the app/helper.
    /// This value is used for accurate status display and should not be used as user intent.
    var effectiveMonitoringEnabled: Bool {
        get {
            return defaults?.bool(forKey: effectiveMonitoringEnabledKey) ?? false
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.effectiveMonitoringEnabledKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: effectiveMonitoringEnabledKey)
            DistributedNotificationCenter.default().postNotificationName(
                .awdlEffectiveMonitoringStateChanged,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NotificationCenter.default.post(name: .awdlMonitorStateChanged, object: nil)
        }
    }

    /// Last known AWDL state (for widget display)
    var lastKnownState: String {
        get {
            return defaults?.string(forKey: lastStateKey) ?? "unknown"
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.lastStateKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: lastStateKey)
        }
    }

    /// Whether Control Center widget mode is enabled (hides menu bar icon)
    var controlCenterWidgetEnabled: Bool {
        get {
            return defaults?.bool(forKey: controlCenterEnabledKey) ?? false
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.controlCenterEnabledKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: controlCenterEnabledKey)
            NotificationCenter.default.post(name: .controlCenterModeChanged, object: nil)
        }
    }

    /// Whether to auto-enable AWDL blocking when Game Mode is active
    var gameModeAutoDetect: Bool {
        get {
            return defaults?.bool(forKey: gameModeAutoDetectKey) ?? false
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.gameModeAutoDetectKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: gameModeAutoDetectKey)
            NotificationCenter.default.post(name: .gameModeAutoDetectChanged, object: nil)
        }
    }

    /// Whether to show the app icon in the Dock
    var showDockIcon: Bool {
        get {
            return defaults?.bool(forKey: showDockIconKey) ?? false
        }
        set {
            guard let defaults = defaults else {
                log.error("Cannot set \(self.showDockIconKey): defaults is nil")
                return
            }
            defaults.set(newValue, forKey: showDockIconKey)
            NotificationCenter.default.post(name: .dockIconVisibilityChanged, object: nil)
        }
    }
}

extension Notification.Name {
    // Use namespaced notification names to avoid collisions with other apps
    static let awdlMonitoringStateChanged = Notification.Name("com.amesvt.pingwarden.notification.MonitoringStateChanged")
    static let awdlEffectiveMonitoringStateChanged = Notification.Name("com.amesvt.pingwarden.notification.EffectiveMonitoringStateChanged")
    static let awdlMonitorStateChanged = Notification.Name("com.amesvt.pingwarden.notification.MonitorStateChanged")
    static let controlCenterModeChanged = Notification.Name("com.amesvt.pingwarden.notification.ControlCenterModeChanged")
    static let gameModeAutoDetectChanged = Notification.Name("com.amesvt.pingwarden.notification.GameModeAutoDetectChanged")
    static let dockIconVisibilityChanged = Notification.Name("com.amesvt.pingwarden.notification.DockIconVisibilityChanged")
}
