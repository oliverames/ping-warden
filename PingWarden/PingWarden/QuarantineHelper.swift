//
//  QuarantineHelper.swift
//  PingWarden
//
//  Helper to check if the app was downloaded and needs quarantine removal.
//  Provides user guidance for Gatekeeper issues.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import AppKit

/// Utility to detect and explain Gatekeeper quarantine issues without
/// bypassing macOS security controls.
struct QuarantineHelper {
    
    /// Check if the app bundle has quarantine attributes
    static func isQuarantined() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        let attrName = "com.apple.quarantine"

        // withCString keeps the C string valid for exactly the duration of the
        // call. NSString.utf8String's buffer is only guaranteed while its
        // owner is alive, which a bridged temporary does not ensure.
        let size = bundlePath.withCString { path in
            Darwin.getxattr(path, attrName, nil, 0, 0, 0)
        }

        // If size > 0, quarantine attribute exists
        return size > 0
    }
    
    /// Check if the app is code signed (not ad-hoc)
    static func isProperlyCodeSigned() -> Bool {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return false }
        
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        
        // Check for valid signature (not ad-hoc)
        var requirement: SecRequirement?
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] exists"
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }
        
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
    
    /// Show helpful dialog if app is quarantined
    static func showQuarantineHelpIfNeeded() {
        // Run the checks off the main thread: SecStaticCodeCheckValidity
        // hashes the whole bundle (including Sparkle.framework) on the
        // quarantined first-run path, which would stall launch for seconds.
        DispatchQueue.global(qos: .utility).async {
            // Only show if quarantined and not properly signed (most users)
            guard isQuarantined() && !isProperlyCodeSigned() else {
                return
            }
            DispatchQueue.main.async {
                presentQuarantineHelpAlert()
            }
        }
    }

    /// Main-thread only (presents modal alerts).
    @MainActor
    private static func presentQuarantineHelpAlert() {
        do {
            let alert = NSAlert()
            alert.messageText = GatekeeperCopy.title
            alert.informativeText = GatekeeperCopy.message(
                osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            )
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Releases")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                if let url = URL(string: "https://github.com/oliverames/ping-warden/releases/latest") {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }
    }
}
