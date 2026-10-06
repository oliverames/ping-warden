import Foundation

/// An inactive export format. No type in this file reads or writes app state.
enum MigrationStoredValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case string(String)
    case dateEpochSeconds(Double)
    case data(Data)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case bool, integer, real, string, dateEpochSeconds, data }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .bool: self = .bool(try values.decode(Bool.self, forKey: .value))
        case .integer: self = .integer(try values.decode(Int64.self, forKey: .value))
        case .real: self = .real(try values.decode(Double.self, forKey: .value))
        case .string: self = .string(try values.decode(String.self, forKey: .value))
        case .dateEpochSeconds: self = .dateEpochSeconds(try values.decode(Double.self, forKey: .value))
        case .data: self = .data(try values.decode(Data.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try values.encode(Kind.bool, forKey: .type)
            try values.encode(value, forKey: .value)
        case .integer(let value):
            try values.encode(Kind.integer, forKey: .type)
            try values.encode(value, forKey: .value)
        case .real(let value):
            try values.encode(Kind.real, forKey: .type)
            try values.encode(value, forKey: .value)
        case .string(let value):
            try values.encode(Kind.string, forKey: .type)
            try values.encode(value, forKey: .value)
        case .dateEpochSeconds(let value):
            try values.encode(Kind.dateEpochSeconds, forKey: .type)
            try values.encode(value, forKey: .value)
        case .data(let value):
            try values.encode(Kind.data, forKey: .type)
            try values.encode(value, forKey: .value)
        }
    }
}

enum MigrationRead<Value> {
    case available(Value)
    case absent
    case unavailable
}

/// nil means absent; an empty dictionary means an available, empty domain.
struct MigrationPreferenceDomain: Codable, Equatable, Sendable {
    let values: [String: MigrationStoredValue]?
}

/// nil means no file; empty Data means a present file, which must still validate.
struct MigrationBlob: Codable, Equatable, Sendable {
    let bytes: Data?
}

struct MigrationSource: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let signingTeamIdentifier: String
    let appGroupIdentifier: String
    let marketingVersion: String
    let buildVersion: String
}

enum MigrationSessionState: String, Codable, Sendable { case idle, active, transitioning }
enum MigrationLicenseCacheFormat: String, Codable, Sendable {
    case absent, legacyUnsealed, sealedV1Unverified, malformed
}

enum MigrationCutoverBlocker: String, Codable, CaseIterable, Sendable {
    case runtimeCaptureNotIntegrated
    case keychainContinuityNotVerified
    case sourceFreshnessNotGuaranteed
    case importAndRollbackNotImplemented
    case helperCompatibilityNotVerified
    case legacyUnsealedLicenseRequiresCompatibilityPath
    case licenseSealNotVerified
    case activeSessionNotFinalized

    static let permanent: [Self] = [
        .runtimeCaptureNotIntegrated, .keychainContinuityNotVerified,
        .sourceFreshnessNotGuaranteed, .importAndRollbackNotImplemented,
        .helperCompatibilityNotVerified,
    ]
}

struct MigrationCutoverReadiness: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case notReady }
    let status: Status
    let reasons: [MigrationCutoverBlocker]
}

enum MigrationValidationIssue: String, Codable, Sendable {
    case historicalDashboardInterval
    case historicalPingTarget
}

struct MigrationSnapshot: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let capturedAtEpochSeconds: Double
    let source: MigrationSource
    let sharedPreferences: MigrationPreferenceDomain
    let standardPreferences: MigrationPreferenceDomain
    let licenseCache: [String: MigrationStoredValue]
    let licenseCacheFormat: MigrationLicenseCacheFormat
    let completedSessions: MigrationBlob
    let completedSessionCount: Int
    let sessionState: MigrationSessionState
    let cutoverReadiness: MigrationCutoverReadiness
    let validationIssues: [MigrationValidationIssue]
}

/// Errors deliberately contain no rejected key, value, blob or license content.
enum MigrationSnapshotError: Error, Equatable {
    case unavailableSource
    case unknownField
    case invalidValue
    case malformedBlob
    case duplicateRecordID
    case sizeLimitExceeded
    case unsupportedFormat
    case unsupportedSchema
    case malformedDocument
    case digestMismatch
    case inconsistentMetadata
}

enum MigrationSnapshotBuilder {
    static let maximumPayloadBytes = 12 * 1024 * 1024
    static let maximumStringBytes = 64 * 1024

    private enum ValueKind { case bool, count, real, string, date, data }

    private static let sharedKinds: [String: ValueKind] = [
        "AWDLMonitoringEnabled": .bool, "ProtectionPauseUntil": .real,
        "ControlCenterWidgetEnabled": .bool, "ControlCenterOnlyEnabled": .bool,
        "GameModeAutoDetect": .bool, "ShowDockIcon": .bool, "ShowMenuDropdownMetrics": .bool,
        "CompletedProtectedSessionCount": .count, "LifetimeInterventionCount": .count,
        "CrashReportingEnabled": .bool, "BetaChannelEnabled": .bool,
        "LastSeenWhatsNewVersion": .string, "WelcomeHasBeenPresented": .bool,
        "DashboardCustomPingTargets": .data, "LegacyAppGroupMigrationCompleted": .bool,
        "LicenseTransitionNoticeShown": .bool, "LicenseTransitionLastPresentedAt": .date,
    ]
    private static let licenseKinds: [String: ValueKind] = [
        "LicenseCachedValid": .bool, "LicenseLastVerifiedAt": .real,
        "LicenseGrandfatherDeadline": .real, "LicenseLastSeenAt": .real,
        "LicenseStateSeal": .string, "LicenseGrandfatherChecked": .bool,
    ]
    private static let standardKinds: [String: ValueKind] = [
        "DashboardSelectedPingTargetID": .string, "DashboardUpdateInterval": .real,
        "NSWindow Frame PingWardenSettings": .string,
    ]

    static func make(
        source: MigrationSource,
        snapshotID: UUID,
        capturedAt: Date,
        sharedValues: MigrationRead<[String: MigrationStoredValue]>,
        standardValues: MigrationRead<[String: MigrationStoredValue]>,
        recapFile: MigrationRead<Data>,
        sessionState: MigrationSessionState
    ) throws -> MigrationSnapshot {
        guard source.bundleIdentifier == "com.amesvt.pingwarden",
              source.signingTeamIdentifier == "PV3W52NDZ3",
              source.appGroupIdentifier == "PV3W52NDZ3.com.amesvt.pingwarden",
              !source.marketingVersion.isEmpty, source.marketingVersion.utf8.count <= 128,
              !source.buildVersion.isEmpty, source.buildVersion.utf8.count <= 128,
              capturedAt.timeIntervalSince1970.isFinite else {
            throw MigrationSnapshotError.invalidValue
        }
        let shared = try available(sharedValues)
        let standard = try available(standardValues)
        let recaps = try available(recapFile)
        try validate(shared ?? [:], kinds: sharedKinds.merging(licenseKinds) { first, _ in first })
        try validate(standard ?? [:], kinds: standardKinds)
        let cache = (shared ?? [:]).filter { licenseKinds[$0.key] != nil }
        let format = classifyLicenseCache(cache)
        guard format != .malformed else { throw MigrationSnapshotError.invalidValue }
        var issues: [MigrationValidationIssue] = []
        if case .data(let targets)? = shared?["DashboardCustomPingTargets"],
           try validateTargets(targets) {
            issues.append(.historicalPingTarget)
        }
        let recapCount = try recaps.map(validateRecaps) ?? 0
        if case .real(let interval)? = standard?["DashboardUpdateInterval"],
           ![1.0, 2.0, 5.0, 10.0].contains(interval) {
            issues.append(.historicalDashboardInterval)
        }
        var blockers = MigrationCutoverBlocker.permanent
        if format == .legacyUnsealed { blockers.append(.legacyUnsealedLicenseRequiresCompatibilityPath) }
        if format == .sealedV1Unverified { blockers.append(.licenseSealNotVerified) }
        if sessionState != .idle { blockers.append(.activeSessionNotFinalized) }
        return MigrationSnapshot(
            snapshotID: snapshotID, capturedAtEpochSeconds: capturedAt.timeIntervalSince1970,
            source: source,
            sharedPreferences: MigrationPreferenceDomain(values: shared.map { values in
                values.filter { licenseKinds[$0.key] == nil }
            }),
            standardPreferences: MigrationPreferenceDomain(values: standard),
            licenseCache: cache, licenseCacheFormat: format,
            completedSessions: MigrationBlob(bytes: recaps), completedSessionCount: recapCount,
            sessionState: sessionState,
            cutoverReadiness: MigrationCutoverReadiness(status: .notReady, reasons: blockers),
            validationIssues: issues
        )
    }

    /// This is format recognition only. Neither a seal nor a paid license is verified.
    static func classifyLicenseCache(_ values: [String: MigrationStoredValue]) -> MigrationLicenseCacheFormat {
        do { try validate(values, kinds: licenseKinds) } catch { return .malformed }
        guard !values.isEmpty else { return .absent }
        guard let storedSeal = values["LicenseStateSeal"] else { return .legacyUnsealed }
        guard case .string(let seal) = storedSeal, isHexDigest(seal),
              values["LicenseCachedValid"] != nil,
              values["LicenseLastVerifiedAt"] != nil,
              values["LicenseGrandfatherDeadline"] != nil,
              values["LicenseLastSeenAt"] != nil else { return .malformed }
        return .sealedV1Unverified
    }

    /// Rebuild derived metadata; a decoded document cannot claim it is ready.
    static func validate(_ snapshot: MigrationSnapshot) throws {
        var shared = snapshot.sharedPreferences.values
        guard shared != nil || snapshot.licenseCache.isEmpty else {
            throw MigrationSnapshotError.inconsistentMetadata
        }
        guard !(shared ?? [:]).keys.contains(where: { licenseKinds[$0] != nil }),
              snapshot.licenseCache.keys.allSatisfy({ licenseKinds[$0] != nil }) else {
            throw MigrationSnapshotError.unknownField
        }
        for (key, value) in snapshot.licenseCache { shared?[key] = value }
        let rebuilt = try make(
            source: snapshot.source, snapshotID: snapshot.snapshotID,
            capturedAt: Date(timeIntervalSince1970: snapshot.capturedAtEpochSeconds),
            sharedValues: shared.map { .available($0) } ?? .absent,
            standardValues: snapshot.standardPreferences.values.map { .available($0) } ?? .absent,
            recapFile: snapshot.completedSessions.bytes.map { .available($0) } ?? .absent,
            sessionState: snapshot.sessionState
        )
        guard rebuilt == snapshot else { throw MigrationSnapshotError.inconsistentMetadata }
    }

    static func isHexDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func available<T>(_ read: MigrationRead<T>) throws -> T? {
        switch read {
        case .available(let value): return value
        case .absent: return nil
        case .unavailable: throw MigrationSnapshotError.unavailableSource
        }
    }

    private static func validate(_ values: [String: MigrationStoredValue], kinds: [String: ValueKind]) throws {
        for (key, value) in values {
            guard let kind = kinds[key] else { throw MigrationSnapshotError.unknownField }
            switch (kind, value) {
            case (.bool, .bool): break
            case (.count, .integer(let count)) where count >= 0: break
            case (.real, .real(let number)) where number.isFinite: break
            case (.date, .dateEpochSeconds(let number)) where number.isFinite: break
            case (.string, .string(let text)):
                guard text.utf8.count <= maximumStringBytes else { throw MigrationSnapshotError.sizeLimitExceeded }
            case (.data, .data(let bytes)):
                guard bytes.count <= maximumPayloadBytes else { throw MigrationSnapshotError.sizeLimitExceeded }
            default: throw MigrationSnapshotError.invalidValue
            }
        }
    }

    private static func validateTargets(_ bytes: Data) throws -> Bool {
        try validateRecordKeys(bytes, allowed: ["id", "displayName", "host", "port"])
        let targets: [CustomPingTarget]
        do { targets = try JSONDecoder().decode([CustomPingTarget].self, from: bytes) }
        catch { throw MigrationSnapshotError.malformedBlob }
        guard Set(targets.map(\.id)).count == targets.count else { throw MigrationSnapshotError.duplicateRecordID }
        var hasHistoricalTarget = false
        for target in targets {
            // Version 4.0 accepted nonempty hosts before today's syntax rules.
            // Preserve those records exactly; this format never activates them.
            let name = target.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = target.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, target.displayName.utf8.count <= maximumStringBytes,
                  !host.isEmpty, host.count <= CustomPingTargetStore.maxHostnameLength,
                  target.port > 0 else { throw MigrationSnapshotError.invalidValue }
            if CustomPingTargetStore.validate(
                displayName: target.displayName, host: target.host, port: Int(target.port)
            ) != nil { hasHistoricalTarget = true }
        }
        return hasHistoricalTarget
    }

    private static func validateRecaps(_ bytes: Data) throws -> Int {
        try validateRecordKeys(bytes, allowed: [
            "id", "startedAt", "endedAt", "trigger", "sampleCount", "successfulSampleCount",
            "medianLatencyMs", "p95LatencyMs", "jitterMs", "packetLossPercent", "interventionCount",
            "endReason", "protectionWasInterrupted",
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recaps: [ProtectedSessionSummary]
        do { recaps = try decoder.decode([ProtectedSessionSummary].self, from: bytes) }
        catch { throw MigrationSnapshotError.malformedBlob }
        guard Set(recaps.map(\.id)).count == recaps.count else { throw MigrationSnapshotError.duplicateRecordID }
        for recap in recaps {
            guard recap.startedAt.timeIntervalSince1970.isFinite, recap.endedAt.timeIntervalSince1970.isFinite,
                  recap.endedAt >= recap.startedAt,
                  recap.sampleCount >= 0, recap.successfulSampleCount >= 0,
                  recap.successfulSampleCount <= recap.sampleCount, recap.interventionCount >= 0,
                  [recap.medianLatencyMs, recap.p95LatencyMs, recap.jitterMs, recap.packetLossPercent]
                    .allSatisfy({ $0.isFinite && $0 >= 0 }),
                  recap.packetLossPercent <= 100 else { throw MigrationSnapshotError.invalidValue }
        }
        return recaps.count
    }

    private static func validateRecordKeys(_ bytes: Data, allowed: Set<String>) throws {
        guard bytes.count <= maximumPayloadBytes else { throw MigrationSnapshotError.sizeLimitExceeded }
        let records: [[String: Any]]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else {
                throw MigrationSnapshotError.malformedBlob
            }
            records = parsed
        } catch { throw MigrationSnapshotError.malformedBlob }
        guard records.allSatisfy({ Set($0.keys).isSubset(of: allowed) }) else {
            throw MigrationSnapshotError.unknownField
        }
    }
}
