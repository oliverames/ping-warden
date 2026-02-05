//
//  AWDLToggleIntent.swift
//  AWDLControlWidget
//
//  App Intent to toggle AWDL monitoring from Control Center.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import AppIntents
import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "WidgetIntent")

/// App Intent to toggle AWDL monitoring (used by Control Widget button)
/// When enabled, continuously monitors and keeps AWDL down.
///
/// Note: This intent updates the shared preference and sends a distributed notification.
/// The main app must be running to actually control the helper daemon via XPC.
/// If the app is not running, we attempt to launch it.
struct ToggleAWDLMonitoringIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AWDL Monitoring"
    static var description = IntentDescription("Toggles AWDL monitoring on or off")

    /// Opens the main app when the intent is performed
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // Toggle the current state
        let currentState = AWDLPreferences.shared.isMonitoringEnabled
        let newState = !currentState
        log.info("Toggling monitoring from \(currentState) to \(newState)")

        // Update shared preferences
        // This posts a distributed notification that the main app observes
        AWDLPreferences.shared.isMonitoringEnabled = newState

        // Verify the change was applied
        let verifiedState = AWDLPreferences.shared.isMonitoringEnabled
        if verifiedState != newState {
            log.error("Failed to toggle monitoring - state mismatch")
            throw AWDLError.toggleFailed
        }

        // Attempt to launch the main app if it's not running
        // This ensures the helper daemon is started/stopped appropriately
        await launchMainAppIfNeeded()

        log.info("Successfully toggled monitoring to \(newState)")
        return .result()
    }

    /// Launch the main app if it's not already running
    private func launchMainAppIfNeeded() async {
        let bundleIdentifier = "com.amesvt.pingwarden"

        // Check if app is already running
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == bundleIdentifier }

        if !isRunning {
            log.info("Main app not running, attempting to launch...")

            // Try to launch the app using its bundle identifier
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false // Don't bring to foreground
                configuration.addsToRecentItems = false

                do {
                    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
                    log.info("Successfully launched main app")
                } catch {
                    log.error("Failed to launch main app: \(error.localizedDescription)")
                }
            } else {
                log.warning("Could not find main app URL for bundle identifier: \(bundleIdentifier)")
            }
        } else {
            log.debug("Main app already running")
        }
    }
}

enum AWDLError: Error, CustomLocalizedStringResourceConvertible {
    case toggleFailed
    case monitoringFailed
    case appLaunchFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .toggleFailed:
            return "Failed to toggle AWDL interface"
        case .monitoringFailed:
            return "Failed to start monitoring"
        case .appLaunchFailed:
            return "Failed to launch Ping Warden app"
        }
    }
}
