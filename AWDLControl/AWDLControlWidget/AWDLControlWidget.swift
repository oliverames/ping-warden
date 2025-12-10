import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center
/// Tap to toggle AWDL monitoring on/off
@main
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleAWDLMonitoringIntent()) {
                Label("Toggle AWDL", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
            .tint(.blue)
        }
        .displayName("AWDL Control")
        .description("Tap to toggle AWDL monitoring")
    }
}
