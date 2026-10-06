//
//  PingWardenWidget.swift
//  PingWardenWidget
//
//  Control Center widget for toggling AWDL blocking.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import SwiftUI
import WidgetKit
import AppIntents

enum PingWardenControlKind {
    static let pingProtection = "PingWardenWidget"
}

#if PINGWARDEN_DORMANT_RECEIVER
/// Constant presentation only. This is not an observation of active protection.
@main
struct PingWardenWidget: ControlWidget {
    static let kind: String = PingWardenControlKind.pingProtection

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetToggle(isOn: false, action: SetPingProtectionIntent()) {
                Label("Migration Pending", systemImage: "clock")
            } valueLabel: { _ in
                Text("Waiting")
            }
        }
        .displayName("Ping Warden Migration")
        .description("Keep using your existing Ping Warden installation while migration is prepared.")
    }
}
#else
/// Control Widget for managing Ping Protection from Control Center.
/// Shows the effective runtime state while saving explicit toggle choices.
@main
struct PingWardenWidget: ControlWidget {
    static let kind: String = PingWardenControlKind.pingProtection

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            // Runtime state can differ from the saved preference while a
            // Latency Session or Game Mode automation is active. Display
            // what the helper is actually doing. The SetValueIntent receives
            // the user's explicit target and persists it after XPC succeeds.
            let isProtected = PingWardenPreferences.shared.effectiveMonitoringEnabled
            ControlWidgetToggle(isOn: isProtected, action: SetPingProtectionIntent()) {
                Label(
                    "Ping Protection",
                    systemImage: isProtected ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            } valueLabel: { isProtected in
                Text(isProtected ? "Protected" : "Not Protected")
            }
            .tint(.blue)
        }
        .displayName("Ping Protection")
        .description("Reduce wireless interruptions during gaming. AirDrop, AirPlay discovery, and Handoff are unavailable while protected.")
    }
}
#endif
