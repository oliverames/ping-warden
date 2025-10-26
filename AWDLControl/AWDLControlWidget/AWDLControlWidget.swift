import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center and menu bar
/// When active, continuously monitors and keeps AWDL down
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetToggle(
                isOn: AWDLPreferences.shared.isMonitoringEnabled,
                action: AWDLToggleIntent(enableMonitoring: !AWDLPreferences.shared.isMonitoringEnabled)
            ) { isOn in
                Label(
                    isOn ? "AWDL Down" : "AWDL Up",
                    systemImage: isOn ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
            }
            .tint(AWDLPreferences.shared.isMonitoringEnabled ? .green : .blue)
        }
        .displayName("AWDL Control")
        .description("Keep AWDL interface down to prevent network ping spikes")
    }
}
