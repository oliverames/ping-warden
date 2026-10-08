import AppKit
import Darwin
import Foundation
import WidgetKit

/// Samples only passive local state when WidgetKit requests a current value.
/// It never contacts the helper, launches the app, or changes saved intent.
///
/// This hardens reloads, not their scheduling: WidgetKit can retain the last
/// rendered value after the app dies. Neither these observations nor a value
/// provider guarantee a post-crash refresh or continued helper ownership.
struct PingProtectionValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        await MainActor.run {
            let preferences = PingWardenPreferences.shared
            guard preferences.usesAppGroupSuite, preferences.effectiveMonitoringEnabled else {
                return false
            }

            let appIsRunning = Self.containingAppIsRunning()
            let interfaceState = appIsRunning ? Self.readAWDLState() : .unknown
            return ControlProtectionState.isProtected(
                usesSharedPreferences: preferences.usesAppGroupSuite,
                effectiveMonitoringEnabled: preferences.effectiveMonitoringEnabled,
                containingAppIsRunning: appIsRunning,
                interfaceState: interfaceState
            )
        }
    }

    @MainActor
    private static func containingAppIsRunning() -> Bool {
        let identifier = "com.amesvt.pingwarden"
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard Bundle(url: appURL)?.bundleIdentifier == identifier else { return false }

        // Do not cache these objects. AppKit's time-varying process properties
        // are snapshots updated with the main run loop and can still race exit.
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { app in
            ControlProtectionState.matchesContainingApp(
                expectedBundleIdentifier: identifier,
                expectedBundleURL: appURL,
                runningBundleIdentifier: app.bundleIdentifier,
                runningBundleURL: app.bundleURL,
                isTerminated: app.isTerminated
            )
        }
    }

    private static func readAWDLState() -> ControlProtectionState.InterfaceState {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return .unknown }
        defer { freeifaddrs(first) }

        var foundAWDL = false
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let entry = interface.pointee
            if let name = entry.ifa_name, String(cString: name) == "awdl0" {
                foundAWDL = true
                // Multiple address records can describe the same interface.
                // Any UP observation vetoes a Protected claim.
                if entry.ifa_flags & UInt32(IFF_UP) != 0 { return .up }
            }
            cursor = entry.ifa_next
        }
        return foundAWDL ? .down : .unknown
    }
}
