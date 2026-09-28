import Foundation

enum DiagnosticsPrivacy {
    static func targetDescription(
        selectedTargetID: String?,
        customTargetIDs: Set<String>
    ) -> String {
        guard let selectedTargetID, !selectedTargetID.isEmpty else {
            return "not selected"
        }
        return customTargetIDs.contains(selectedTargetID.lowercased())
            ? "custom (redacted)"
            : "built-in"
    }

    /// Where the running copy lives, as a category rather than a path, so
    /// the snapshot never carries the account name. A helper registered
    /// from a disk image, a translocated copy, or Downloads stops working
    /// once that copy moves or disappears.
    static func appLocation(bundlePath: String, homeDirectory: String) -> String {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if bundlePath.contains("/AppTranslocation/") { return "translocated" }
        if bundlePath.hasPrefix("/Volumes/") { return "disk_image_or_external_volume" }
        if bundlePath.hasPrefix("/Applications/") { return "applications" }
        if !home.isEmpty {
            if bundlePath.hasPrefix(home + "/Applications/") { return "user_applications" }
            if bundlePath.hasPrefix(home + "/Downloads/") { return "downloads" }
        }
        return "other"
    }

    /// Keys from `launchctl print system/<label>` that describe the job's
    /// health without paths or identifiers from the user's account.
    static let launchdSummaryKeys = [
        "state", "job state", "runs", "last exit code", "last terminating signal",
        "program identifier", "spawn type", "parent bundle version",
    ]

    /// Condenses `launchctl print` output to the whitelisted top-level keys.
    /// A job launchd does not know about exits non-zero (113, "Could not
    /// find service"), which is itself the finding: the registration exists
    /// without a job behind it.
    static func launchdJobSummary(launchctlOutput: String, exitStatus: Int32) -> String {
        // 113 is launchctl's "Could not find service"; other failures say
        // nothing about the job and must not read as a missing one.
        if exitStatus == 113 { return "not_loaded (launchctl exit 113)" }
        guard exitStatus == 0 else { return "unavailable (launchctl exit \(exitStatus))" }
        var values: [String: String] = [:]
        for line in launchctlOutput.split(separator: "\n") {
            // Top-level job properties sit one tab deep; nested dictionaries
            // (environment, endpoints) sit deeper and are skipped.
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t"),
                  let equals = line.range(of: " = ") else { continue }
            let key = line[line.startIndex..<equals.lowerBound].trimmingCharacters(in: .whitespaces)
            guard launchdSummaryKeys.contains(key), values[key] == nil else { continue }
            values[key] = line[equals.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        let parts = launchdSummaryKeys.compactMap { key in values[key].map { "\(key)=\($0)" } }
        return parts.isEmpty ? "loaded (no summary fields)" : parts.joined(separator: "; ")
    }
}
