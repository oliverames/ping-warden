// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

/// Why a request to the helper did not succeed. Only `.declined` means the
/// helper actually answered; every other case means it never did.
enum HelperCommandFailure: Equatable, Sendable {
    /// No XPC connection could be created.
    case noConnection
    /// The helper never replied within the command's deadline.
    case timedOut
    /// The connection failed with an XPC error. The numeric code alone
    /// does not establish why the helper did not answer.
    case rejected(code: Int)
    /// The helper replied and reported that the change failed.
    case declined

    var helperDidNotAnswer: Bool {
        self != .declined
    }

    /// Describe the observed connection failure without guessing whether a
    /// helper rejected it or launchd could not find a running service.
    var diagnosticDescription: String {
        switch self {
        case .noConnection:
            return "no connection to the helper could be made"
        case .timedOut:
            return "the helper did not answer (timed out)"
        case .rejected(let code) where code == HelperRecovery.xpcConnectionInterruptedCode:
            return "the connection to the helper was interrupted (XPC error \(code))"
        case .rejected(let code) where code == HelperRecovery.xpcConnectionInvalidCode:
            return "the connection to the helper was invalid (XPC error \(code))"
        case .rejected(let code):
            return "the connection to the helper failed (XPC error \(code))"
        case .declined:
            return "the helper reported a failure"
        }
    }
}

/// Pure decisions for a helper whose system registration and launchd job
/// disagree. Background Task Management can report the helper as enabled
/// while launchd never starts it, so every XPC request times out. These
/// rules keep that state from producing false errors or false successes.
enum HelperRecovery {
    /// `NSXPCConnectionInterrupted`, kept here so the rule stays
    /// Foundation-only and testable.
    static let xpcConnectionInterruptedCode = 4097
    static let xpcConnectionInvalidCode = 4099

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

    struct InterfaceHealth: Equatable, Sendable {
        let isHealthy: Bool
        let summary: String
    }

    /// The helper test's reading of awdl0. Only an interface that reads up
    /// while protection is requested is a failure; a Mac without awdl0 has
    /// nothing to block, not an interface that is "still up".
    static func interfaceHealth(protectionRequested: Bool, interfaceUp: Bool?) -> InterfaceHealth {
        switch interfaceUp {
        case .some(true) where protectionRequested:
            return InterfaceHealth(
                isHealthy: false,
                summary: "Protection is active, but the wireless interface is still up. The helper may not be working."
            )
        case .some(true):
            return InterfaceHealth(isHealthy: true, summary: "Ping Protection is off.")
        case .some(false):
            return InterfaceHealth(isHealthy: true, summary: "Ping Protection is on.")
        case .none:
            return InterfaceHealth(isHealthy: true, summary: "This Mac has no awdl0 interface to block.")
        }
    }

    /// Turning Ping Protection off always asks the helper first, because
    /// only the helper knows whether it is still enforcing; a single
    /// interface sample can catch the instant macOS re-raised awdl0 while
    /// the helper holds it down. This rule decides whether Off may still
    /// report success after that stop failed or went unanswered: only when
    /// this app neither requested, confirmed, nor had an enable pending,
    /// and awdl0 reads up now. When the interface cannot be read, the
    /// failure stands.
    static func offSatisfiedWithoutHelper(
        wasRequested: Bool,
        wasActive: Bool,
        enablePending: Bool,
        interfaceUp: Bool?
    ) -> Bool {
        guard !wasRequested, !wasActive, !enablePending else { return false }
        return interfaceUp == true
    }
}
