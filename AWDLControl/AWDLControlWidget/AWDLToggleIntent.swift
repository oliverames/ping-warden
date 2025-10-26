import AppIntents
import Foundation

/// App Intent to toggle AWDL monitoring (used by Control Widget button)
/// When enabled, continuously monitors and keeps AWDL down
@available(macOS 26.0, *)
struct ToggleAWDLMonitoringIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AWDL Monitoring"
    static var description = IntentDescription("Toggles AWDL monitoring on or off")

    func perform() async throws -> some IntentResult {
        // Toggle the current state
        let newState = !AWDLPreferences.shared.isMonitoringEnabled
        print("ToggleAWDLMonitoringIntent: Toggling monitoring to \(newState)")

        // Update shared preferences
        // The main app polls this and will start/stop the daemon accordingly
        AWDLPreferences.shared.isMonitoringEnabled = newState

        return .result()
    }
}

enum AWDLError: Error, CustomLocalizedStringResourceConvertible {
    case toggleFailed
    case monitoringFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .toggleFailed:
            return "Failed to toggle AWDL interface"
        case .monitoringFailed:
            return "Failed to start monitoring"
        }
    }
}
