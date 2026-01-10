import AppIntents
import Foundation
import os.log

private let log = Logger(subsystem: "com.awdlcontrol.widget", category: "Intent")

/// App Intent to toggle AWDL monitoring (used by Control Widget button)
/// When enabled, continuously monitors and keeps AWDL down
struct ToggleAWDLMonitoringIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AWDL Monitoring"
    static var description = IntentDescription("Toggles AWDL monitoring on or off")

    func perform() async throws -> some IntentResult {
        // Toggle the current state
        let currentState = AWDLPreferences.shared.isMonitoringEnabled
        let newState = !currentState
        log.info("Toggling monitoring from \(currentState) to \(newState)")

        // Update shared preferences
        // The main app polls this and will start/stop the daemon accordingly
        AWDLPreferences.shared.isMonitoringEnabled = newState

        // Verify the change was applied
        let verifiedState = AWDLPreferences.shared.isMonitoringEnabled
        if verifiedState != newState {
            log.error("Failed to toggle monitoring - state mismatch")
            throw AWDLError.toggleFailed
        }

        log.info("Successfully toggled monitoring to \(newState)")
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
