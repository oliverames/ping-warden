import AppIntents
import Foundation

/// App Intent to toggle AWDL monitoring (not just a one-time toggle)
/// When enabled, continuously monitors and keeps AWDL down
struct ToggleAWDLIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AWDL Monitoring"
    static var description = IntentDescription("Starts or stops continuous AWDL monitoring")

    func perform() async throws -> some IntentResult {
        // Toggle the current state
        let newState = !AWDLPreferences.shared.isMonitoringEnabled
        print("ToggleAWDLIntent: Toggle monitoring to \(newState)")

        // Update shared preferences
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
