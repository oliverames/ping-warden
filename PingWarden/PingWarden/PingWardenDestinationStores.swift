// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

#if os(macOS)
import Darwin
import Foundation

enum PingWardenDestinationStoreError: Error {
    case groupUnavailable
    case sharedDefaultsUnavailable
    case applicationDefaultsUnavailable
}

/// Explicit handles for later injection into the receiving runtime. This has no
/// singleton, source-store fallback, migration, default registration or teardown.
/// Opening handles does not authorize activation or verify durable writes.
final class PingWardenDestinationStores {
    let namespace: PingWardenDestinationNamespace
    let sharedDefaults: UserDefaults
    let applicationDefaults: UserDefaults
    let recapDirectory: URL

    private init(
        namespace: PingWardenDestinationNamespace,
        sharedDefaults: UserDefaults,
        applicationDefaults: UserDefaults,
        recapDirectory: URL
    ) {
        self.namespace = namespace
        self.sharedDefaults = sharedDefaults
        self.applicationDefaults = applicationDefaults
        self.recapDirectory = recapDirectory
    }

    /// Only use after a future receiving-process composition root deliberately
    /// selects this namespace. Do not call from the dormant receiver or source
    /// app. macOS can return a container URL even for an invalid group, so a URL
    /// alone is insufficient. An absent or inaccessible container is an error.
    /// No explicit directory creation, permission repair or probe-write is used.
    /// The system container resolver's own behavior is outside this adapter.
    static func openExisting(fileManager: FileManager = .default) throws -> PingWardenDestinationStores {
        let namespace = PingWardenDestinationNamespace()
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: namespace.sharedDomain
        ), container.isFileURL,
           container.lastPathComponent == namespace.sharedDomain,
           container.standardizedFileURL.path == container.path,
           container.resolvingSymlinksInPath().path == container.path else {
            throw PingWardenDestinationStoreError.groupUnavailable
        }

        let descriptor = container.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw PingWardenDestinationStoreError.groupUnavailable }
        defer { Darwin.close(descriptor) }

        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              opened.st_uid == getuid(),
              Darwin.faccessat(descriptor, ".", R_OK | W_OK | X_OK, 0) == 0 else {
            throw PingWardenDestinationStoreError.groupUnavailable
        }

        guard let shared = UserDefaults(suiteName: namespace.sharedDomain) else {
            throw PingWardenDestinationStoreError.sharedDefaultsUnavailable
        }
        guard let application = UserDefaults(suiteName: namespace.applicationDomain) else {
            throw PingWardenDestinationStoreError.applicationDefaultsUnavailable
        }

        // A bounded check against replacement during construction, not a lease
        // or a promise that another process cannot change paths after return.
        var current = stat()
        let unchanged = container.path.withCString { Darwin.lstat($0, &current) == 0 }
        guard unchanged, current.st_dev == opened.st_dev, current.st_ino == opened.st_ino,
              container.resolvingSymlinksInPath().path == container.path else {
            throw PingWardenDestinationStoreError.groupUnavailable
        }

        return PingWardenDestinationStores(
            namespace: namespace,
            sharedDefaults: shared,
            applicationDefaults: application,
            recapDirectory: namespace.recapDirectory(in: container)
        )
    }

    /// The existing store already accepts an explicit directory. This creates
    /// only its handle. It must not be used to decode/re-encode a migration blob.
    func makeProtectedSessionStore() -> ProtectedSessionStore {
        ProtectedSessionStore(directoryURL: recapDirectory)
    }
}
#endif
