import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center and menu bar
/// When active, continuously monitors and keeps AWDL down
@available(macOS 26.0, *)
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleAWDLIntent()) {
                Label(
                    AWDLPreferences.shared.isMonitoringEnabled ? "AWDL Down" : "AWDL Up",
                    systemImage: AWDLPreferences.shared.isMonitoringEnabled ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            }
            .tint(AWDLPreferences.shared.isMonitoringEnabled ? .green : .blue)
        }
        .displayName("AWDL Control")
        .description("Keep AWDL interface down to prevent network ping spikes")
    }
}
