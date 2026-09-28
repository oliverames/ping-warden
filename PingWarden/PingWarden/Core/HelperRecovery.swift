// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// Pure decisions for a helper whose system registration and launchd job
/// disagree. Background Task Management can report the helper as enabled
/// while launchd never starts it, so every XPC request times out. These
/// rules keep that state from producing false errors or false successes.
enum HelperRecovery {
    /// Reads an `ifconfig awdl0` flags line such as
    /// `awdl0: flags=8943<UP,BROADCAST,RUNNING> mtu 1484`.
    /// Returns `nil` when the line carries no flag list, for example when
    /// the interface does not exist or `ifconfig` failed.
    static func interfaceIsUp(flagsLine: String) -> Bool? {
        guard let flagsRange = flagsLine.range(of: "flags="),
              let open = flagsLine[flagsRange.upperBound...].firstIndex(of: "<"),
              let close = flagsLine[open...].firstIndex(of: ">") else {
            return nil
        }
        let flags = flagsLine[flagsLine.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return flags.contains("UP")
    }

    /// Turning Ping Protection off needs no helper command when this app
    /// neither requested nor confirmed protection and AWDL is demonstrably
    /// available: either the helper last confirmed the interface up, or the
    /// interface reads up right now. The helper keeps awdl0 down while it
    /// enforces, so an interface that is up is not being blocked. When the
    /// interface cannot be read, the helper stays the only authority.
    static func disableAlreadySatisfied(
        isRequested: Bool,
        isActive: Bool,
        lastKnownState: String,
        interfaceUp: Bool?
    ) -> Bool {
        guard !isRequested, !isActive else { return false }
        return lastKnownState == "up" || interfaceUp == true
    }
}
