import AppIntents
import Foundation

/// App Intent to toggle AWDL monitoring (not just a one-time toggle)
/// When enabled, continuously monitors and keeps AWDL down
struct AWDLToggleIntent: AppIntent, ForegroundContinuableIntent {
    static var title: LocalizedStringResource = "Toggle AWDL Monitoring"
    static var description = IntentDescription("Starts or stops continuous AWDL monitoring")

    @Parameter(title: "Enable Monitoring")
    var enableMonitoring: Bool

    init() {
        self.enableMonitoring = false
    }

    init(enableMonitoring: Bool) {
        self.enableMonitoring = enableMonitoring
    }

    func perform() async throws -> some IntentResult {
        print("AWDLToggleIntent: Toggle monitoring to \(enableMonitoring)")

        // Update shared preferences
        AWDLPreferences.shared.isMonitoringEnabled = enableMonitoring

        // Request to continue in foreground to ensure monitoring runs
        // This will launch the app if it's not running
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
