// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// Destinations for a future receiving runtime. These are not source identity
/// metadata and must never replace MigrationSnapshot.source or its domain tags.
/// No caller selects this namespace automatically, including the dormant app.
struct PingWardenDestinationNamespace {
    let sharedDomain = "84M4ZF255G.com.amesvt.pingwarden"
    let applicationDomain = "com.amesvt.pingwarden.receiver"

    func recapDirectory(in groupContainer: URL) -> URL {
        groupContainer
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Ping Warden", isDirectory: true)
    }
}
