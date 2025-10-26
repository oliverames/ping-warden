import AppIntents
import Foundation

/// App Intent to toggle AWDL interface state
struct AWDLToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AWDL"
    static var description = IntentDescription("Toggles the AWDL interface on or off")

    @Parameter(title: "New State")
    var newState: Bool

    init() {
        self.newState = false
    }

    init(newState: Bool) {
        self.newState = newState
    }

    func perform() async throws -> some IntentResult {
        // Get the shared AWDL manager
        let manager = AWDLManager.shared

        // Toggle based on the new state
        let success: Bool
        if newState {
            success = manager.bringDown()
        } else {
            success = manager.bringUp()
        }

        if !success {
            throw AWDLError.toggleFailed
        }

        return .result()
    }
}

enum AWDLError: Error, CustomLocalizedStringResourceConvertible {
    case toggleFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .toggleFailed:
            return "Failed to toggle AWDL interface"
        }
    }
}
