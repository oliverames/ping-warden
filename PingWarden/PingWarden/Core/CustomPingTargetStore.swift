//
//  CustomPingTargetStore.swift
//  PingWarden
//
//  Persists user-defined ping targets to UserDefaults (App Group). Defaults
//  injection lets the test suite hit an in-memory suite without polluting
//  the real container.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Plain Codable record. Distinct from the view-layer `PingTarget` so this
/// file stays pure Foundation and the test suite can exercise it via
/// `swift test`.
struct CustomPingTarget: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var host: String
    var port: UInt16

    init(id: UUID = UUID(), displayName: String, host: String, port: UInt16) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
    }
}

enum CustomPingTargetValidationError: Error, Equatable {
    case nameEmpty
    case hostEmpty
    case hostInvalid
    case hostTooLong
    case portOutOfRange

    var userMessage: String {
        switch self {
        case .nameEmpty:
            return "Give the server a name."
        case .hostEmpty:
            return "Enter a hostname or IP address."
        case .hostInvalid:
            return "Enter only a hostname or IP address, without a URL, path, or port. Use the Port field below."
        case .hostTooLong:
            return "Hostname is too long (255 characters max)."
        case .portOutOfRange:
            return "Port must be between 1 and 65535."
        }
    }
}

final class CustomPingTargetStore {
    private let userDefaults: UserDefaults
    private let storageKey = "DashboardCustomPingTargets"
    private let lock = NSLock()

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// Total length of a hostname per RFC 1035 — the same limit our
    /// existing TCPProbe smoke test relies on to force a resolver failure.
    static let maxHostnameLength = 255

    /// Validate user input. Returns `nil` on success or the first failure
    /// reason. Trim whitespace before calling.
    static func validate(displayName: String, host: String, port: Int) -> CustomPingTargetValidationError? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return .nameEmpty
        }
        if trimmedHost.isEmpty {
            return .hostEmpty
        }
        if trimmedHost.count > maxHostnameLength {
            return .hostTooLong
        }
        if !isHost(trimmedHost) { return .hostInvalid }
        if port < 1 || port > 65535 {
            return .portOutOfRange
        }
        return nil
    }

    private static func isHost(_ host: String) -> Bool {
        if host.contains(":") {
            // A bare IPv6 address may include a local interface scope, as
            // accepted by getaddrinfo. URL brackets and host:port are rejected.
            let pieces = host.split(separator: "%", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let address = pieces.first else { return false }
            if pieces.count == 2 {
                let scope = pieces[1]
                guard !scope.isEmpty, scope.unicodeScalars.allSatisfy({
                    CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
                }) else { return false }
            }
            var parsed = in6_addr()
            return String(address).withCString { inet_pton(AF_INET6, $0, &parsed) == 1 }
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        return !name.isEmpty && name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        }
    }

    func load() -> [CustomPingTarget] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    @discardableResult
    func save(_ targets: [CustomPingTarget]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return saveLocked(targets)
    }

    // Mutations hold the lock across the whole read-modify-write so
    // concurrent callers cannot interleave and lose writes.

    @discardableResult
    func add(_ target: CustomPingTarget) -> [CustomPingTarget] {
        lock.lock()
        defer { lock.unlock() }
        var targets = loadLocked()
        targets.append(target)
        saveLocked(targets)
        return targets
    }

    @discardableResult
    func remove(id: UUID) -> [CustomPingTarget] {
        lock.lock()
        defer { lock.unlock() }
        var targets = loadLocked()
        targets.removeAll { $0.id == id }
        saveLocked(targets)
        return targets
    }

    @discardableResult
    func update(_ target: CustomPingTarget) -> [CustomPingTarget] {
        lock.lock()
        defer { lock.unlock() }
        var targets = loadLocked()
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
            saveLocked(targets)
        }
        return targets
    }

    private func loadLocked() -> [CustomPingTarget] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([CustomPingTarget].self, from: data)
        } catch {
            // A corrupted blob shouldn't lock the user out of the feature.
            // We surface an empty list and overwrite on the next save.
            return []
        }
    }

    @discardableResult
    private func saveLocked(_ targets: [CustomPingTarget]) -> Bool {
        do {
            let data = try JSONEncoder().encode(targets)
            userDefaults.set(data, forKey: storageKey)
            return true
        } catch {
            return false
        }
    }
}
