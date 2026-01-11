//
//  AWDLControlWidget.swift
//  AWDLControlWidget
//
//  Control Center widget for toggling AWDL blocking.
//
//  Copyright (c) 2025 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center
/// Shows current state and allows toggling AWDL monitoring on/off
@main
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleAWDLMonitoringIntent()) {
                let isOn = AWDLPreferences.shared.isMonitoringEnabled
                Label(
                    isOn ? "AWDL Blocked" : "AWDL Allowed",
                    systemImage: isOn ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            }
            .tint(.blue)
        }
        .displayName("AWDL Control")
        .description("Toggle AWDL blocking to reduce network latency")
    }
}
