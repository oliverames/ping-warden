//
//  ControlCenterSupport.swift
//  PingWarden
//
//  Centralized capability checks for Control Center widget mode.
//

import Foundation
import os.log
import Security
#if canImport(WidgetKit)
import WidgetKit
#endif

enum ControlCenterSupport {
    /// Must match `PingWardenControlKind.pingProtection` in the widget target.
    static let pingProtectionControlKind = "PingWardenWidget"

    /// Ask Control Center to re-render the Ping Protection toggle. The main
    /// app must call this whenever the monitoring intent or effective state
    /// changes — the widget only re-reads shared defaults when reloaded, so
    /// without this a menu-bar or Game Mode toggle leaves the Control Center
    /// toggle displaying stale state indefinitely.
    static func reloadPingProtectionControl() {
        #if canImport(WidgetKit)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: pingProtectionControlKind)
        }
        #endif
    }

    /// Reload the control after a recovery point (#101), coalesced with any
    /// other recovery reload requested in the same short window. Use this
    /// rather than `reloadPingProtectionControl()` for launch, helper
    /// recovery, Repair, and wake, which can arrive together.
    @MainActor
    static func requestPingProtectionRefresh(_ trigger: ControlCenterRefreshTrigger) {
        ControlCenterRefresher.shared.request(trigger)
    }

    enum Availability: Equatable {
        case available
        case unsupportedOS
        case missingWidgetExtension
        case unsignedOrUntrusted

        var isAvailable: Bool {
            self == .available
        }

        var statusText: String {
            switch self {
            case .available:
                return "Ready"
            case .unsupportedOS, .missingWidgetExtension, .unsignedOrUntrusted:
                return "Unavailable"
            }
        }

        /// Describes the setting. The reason it is unavailable appears once,
        /// in `footerText`, beside the Unavailable badge.
        var detailText: String {
            InterfaceVisibilityCopy.controlCenterOnlyDetail
        }

        var footerText: String {
            switch self {
            case .available:
                // What each mode hides is explained by
                // InterfaceVisibilityCopy.interfaceFooter(mode:).
                return InterfaceVisibilityCopy.addControlInstruction
            case .unsupportedOS:
                return "Control Center widgets in Ping Warden require macOS 26 or newer."
            case .missingWidgetExtension:
                return "The Ping Warden widget extension was not found in this app bundle. Reinstall Ping Warden from a signed release."
            case .unsignedOrUntrusted:
                return "Control Center widgets require the app to be signed with Ping Warden's Developer ID certificate."
            }
        }
    }

    static func isAvailableForCurrentApp() -> Bool {
        availabilityForCurrentApp().isAvailable
    }

    /// The signature check costs tens of milliseconds and runs on the main
    /// thread from window-close and Settings paths. Neither the OS version
    /// nor the running bundle's signature changes while the process runs;
    /// an update replaces the bundle and relaunches.
    private static let cachedAvailability = evaluateAvailability()

    static func availabilityForCurrentApp() -> Availability {
        cachedAvailability
    }

    private static func evaluateAvailability() -> Availability {
        guard #available(macOS 26.0, *) else {
            return .unsupportedOS
        }

        guard let widgetURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("PingWardenWidget.appex"),
              let widgetBundle = Bundle(url: widgetURL),
              let extensionInfo = widgetBundle.infoDictionary?["NSExtension"] as? [String: Any],
              extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension" else {
            return .missingWidgetExtension
        }

        guard let bundleURL = Bundle.main.bundleURL as CFURL? else {
            return .unsignedOrUntrusted
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return .unsignedOrUntrusted
        }

        var requirement: SecRequirement?
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"PV3W52NDZ3\""
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            return .unsignedOrUntrusted
        }

        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess ? .available : .unsignedOrUntrusted
    }
}

/// Schedules coalesced Control Center reloads for recovery points (#101).
/// A crashed process cannot reload the control, so the next process does it
/// at launch, and recovery paths that may not write the effective-state
/// preference (helper answering again, Repair, wake) do it as well. The
/// widget's value provider then re-derives the state from the running app
/// and the live awdl0 flags instead of WidgetKit's cached rendering.
@MainActor
final class ControlCenterRefresher {
    static let shared = ControlCenterRefresher()

    private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "ControlCenter")
    private var coalescer = ControlCenterRefreshCoalescer()

    private init() {}

    func request(_ trigger: ControlCenterRefreshTrigger) {
        guard let delay = coalescer.request(
            trigger,
            controlCenterAvailable: ControlCenterSupport.isAvailableForCurrentApp()
        ) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.flush()
        }
    }

    private func flush() {
        let triggers = coalescer.flush()
        guard !triggers.isEmpty else { return }
        let reasons = triggers.map(\.rawValue).joined(separator: ",")
        log.info("Reloading the Ping Protection control (\(reasons, privacy: .public))")
        ControlCenterSupport.reloadPingProtectionControl()
    }
}
