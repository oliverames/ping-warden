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
            ControlWidgetToggle(
                "AWDL Block",
                isOn: AWDLPreferences.shared.isMonitoringEnabled,
                action: ToggleAWDLMonitoringIntent()
            ) { isOn in
                Label(
                    isOn ? "Blocking" : "Allowed",
                    systemImage: isOn ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            }
            .tint(.blue)
        }
        .displayName("AWDL Control")
        .description("Toggle AWDL blocking to reduce network latency")
    }
}
