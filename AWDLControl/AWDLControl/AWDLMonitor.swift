import Foundation
import Network

/// Continuously monitors and keeps AWDL interface down
/// This is the core functionality that mirrors awdlkiller's behavior
class AWDLMonitor {
    static let shared = AWDLMonitor()

    private var monitoringTimer: Timer?
    private let checkInterval: TimeInterval = 0.5 // Check every 500ms
    private let manager = AWDLManager.shared
    private var isMonitoring = false

    private init() {
        // Restore monitoring state on app launch
        if AWDLPreferences.shared.isMonitoringEnabled {
            startMonitoring()
        }
    }

    /// Start continuous monitoring to keep AWDL down
    func startMonitoring() {
        guard !isMonitoring else {
            print("AWDLMonitor: Already monitoring")
            return
        }

        print("AWDLMonitor: Starting continuous monitoring")
        isMonitoring = true
        AWDLPreferences.shared.isMonitoringEnabled = true

        // Bring down immediately
        _ = manager.bringDown()

        // Start timer to continuously check and keep down
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkAndBringDown()
        }

        // Ensure timer runs even when UI is not active
        if let timer = monitoringTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    /// Stop continuous monitoring and allow AWDL to come up
    func stopMonitoring(bringUp: Bool = true) {
        guard isMonitoring else {
            print("AWDLMonitor: Not currently monitoring")
            return
        }

        print("AWDLMonitor: Stopping continuous monitoring")
        isMonitoring = false
        AWDLPreferences.shared.isMonitoringEnabled = false

        // Stop timer
        monitoringTimer?.invalidate()
        monitoringTimer = nil

        // Optionally bring interface back up
        if bringUp {
            _ = manager.bringUp()
        }
    }

    /// Check AWDL state and bring it down if it's up
    /// This is called repeatedly by the timer
    private func checkAndBringDown() {
        let state = manager.getInterfaceState()

        switch state {
        case .up:
            print("AWDLMonitor: Detected AWDL up, bringing down...")
            let success = manager.bringDown()
            AWDLPreferences.shared.lastKnownState = success ? "down" : "error"

            if !success {
                print("AWDLMonitor: Warning - Failed to bring AWDL down")
            }

        case .down:
            // Good, it's down - update state silently
            AWDLPreferences.shared.lastKnownState = "down"

        case .unknown:
            print("AWDLMonitor: Warning - Unable to determine AWDL state")
            AWDLPreferences.shared.lastKnownState = "unknown"
        }
    }

    /// Check if monitoring is currently active
    var isMonitoringActive: Bool {
        return isMonitoring
    }
}
