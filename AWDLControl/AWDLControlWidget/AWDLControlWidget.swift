import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center and menu bar
/// Tap to toggle AWDL monitoring on/off
@available(macOS 26.0, *)
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    @available(macOS 26.0, *)
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
