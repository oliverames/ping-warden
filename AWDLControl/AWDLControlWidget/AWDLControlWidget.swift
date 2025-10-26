import SwiftUI
import WidgetKit
import AppIntents

/// Control Widget for managing AWDL interface from Control Center and menu bar
struct AWDLControlWidget: ControlWidget {
    static let kind: String = "AWDLControlWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetToggle(
                isOn: AWDLManager.shared.isAWDLDown,
                action: AWDLToggleIntent(newState: !AWDLManager.shared.isAWDLDown)
            ) { isOn in
                Label(isOn ? "AWDL Down" : "AWDL Up", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tint(.blue)
        }
        .displayName("AWDL Control")
        .description("Toggle the AWDL (Apple Wireless Direct Link) interface")
    }
}
