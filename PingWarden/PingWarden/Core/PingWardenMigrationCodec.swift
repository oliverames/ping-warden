#if canImport(CryptoKit)
// Native macOS export codec; the typed snapshot builder remains platform-independent.
import CryptoKit
import Foundation

enum MigrationSnapshotCodec {
    static let format = "com.amesvt.pingwarden.migration-snapshot"
    static let schemaVersion = 1
    static let maximumEnvelopeBytes = 16 * 1024 * 1024

    private struct Envelope: Codable {
        let format: String
        let schemaVersion: Int
        let payload: Data
        let payloadSHA256: String
    }

    static func encode(_ snapshot: MigrationSnapshot) throws -> Data {
        try MigrationSnapshotBuilder.validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(snapshot)
        guard payload.count <= MigrationSnapshotBuilder.maximumPayloadBytes else {
            throw MigrationSnapshotError.sizeLimitExceeded
        }
        let data = try encoder.encode(Envelope(
            format: format, schemaVersion: schemaVersion, payload: payload, payloadSHA256: digest(payload)
        ))
        guard data.count <= maximumEnvelopeBytes else { throw MigrationSnapshotError.sizeLimitExceeded }
        return data
    }

    static func decode(_ data: Data) throws -> MigrationSnapshot {
        guard data.count <= maximumEnvelopeBytes else { throw MigrationSnapshotError.sizeLimitExceeded }
        do {
            _ = try object(data, keys: ["format", "schemaVersion", "payload", "payloadSHA256"])
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.format == format else { throw MigrationSnapshotError.unsupportedFormat }
            guard envelope.schemaVersion == schemaVersion else { throw MigrationSnapshotError.unsupportedSchema }
            guard envelope.payload.count <= MigrationSnapshotBuilder.maximumPayloadBytes else {
                throw MigrationSnapshotError.sizeLimitExceeded
            }
            guard MigrationSnapshotBuilder.isHexDigest(envelope.payloadSHA256),
                  envelope.payloadSHA256 == digest(envelope.payload) else {
                throw MigrationSnapshotError.digestMismatch
            }
            try validatePayloadKeys(envelope.payload)
            let snapshot = try JSONDecoder().decode(MigrationSnapshot.self, from: envelope.payload)
            try MigrationSnapshotBuilder.validate(snapshot)
            return snapshot
        } catch let error as MigrationSnapshotError {
            throw error
        } catch {
            // Decoder descriptions can contain input values. Never propagate them.
            throw MigrationSnapshotError.malformedDocument
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        try object(JSONSerialization.jsonObject(with: data), keys: keys)
    }

    private static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw MigrationSnapshotError.malformedDocument }
        guard Set(value.keys).isSubset(of: keys) else { throw MigrationSnapshotError.unknownField }
        return value
    }

    private static func validatePayloadKeys(_ data: Data) throws {
        let payload = try object(data, keys: [
            "snapshotID", "capturedAtEpochSeconds", "source", "sharedPreferences", "standardPreferences",
            "licenseCache", "licenseCacheFormat", "completedSessions", "completedSessionCount",
            "sessionState", "cutoverReadiness", "validationIssues",
        ])
        _ = try object(payload["source"], keys: [
            "bundleIdentifier", "signingTeamIdentifier", "appGroupIdentifier", "marketingVersion", "buildVersion",
        ])
        for key in ["sharedPreferences", "standardPreferences"] {
            let domain = try object(payload[key], keys: ["values"])
            if let values = domain["values"], !(values is NSNull) { try validateStoredValueKeys(values) }
        }
        try validateStoredValueKeys(payload["licenseCache"])
        _ = try object(payload["completedSessions"], keys: ["bytes"])
        _ = try object(payload["cutoverReadiness"], keys: ["status", "reasons"])
    }

    private static func validateStoredValueKeys(_ value: Any?) throws {
        guard let values = value as? [String: Any] else { throw MigrationSnapshotError.malformedDocument }
        for stored in values.values { _ = try object(stored, keys: ["type", "value"]) }
        // The builder checks domain-specific allowed names and exact value kinds.
    }
}

#endif
