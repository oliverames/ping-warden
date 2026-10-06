#if canImport(CryptoKit)
// The migration codec is macOS-only. Portable core tests remain available on Linux.
import CryptoKit
import Foundation
import XCTest
@testable import PingWardenCore

final class PingWardenMigrationSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let snapshotID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let source = MigrationSource(
        bundleIdentifier: "com.amesvt.pingwarden", signingTeamIdentifier: "PV3W52NDZ3",
        appGroupIdentifier: "PV3W52NDZ3.com.amesvt.pingwarden", marketingVersion: "4.0.0", buildVersion: "40000"
    )

    private var legacyPaid: [String: MigrationStoredValue] {
        [
            "AWDLMonitoringEnabled": .bool(true), "LicenseCachedValid": .bool(true),
            "LicenseLastVerifiedAt": .real(1_799_999_400), "LicenseGrandfatherChecked": .bool(true),
            "CrashReportingEnabled": .bool(false),
        ]
    }

    private var sealedCache: [String: MigrationStoredValue] {
        [
            "LicenseCachedValid": .bool(true), "LicenseLastVerifiedAt": .real(1_799_999_400),
            "LicenseGrandfatherDeadline": .real(0), "LicenseLastSeenAt": .real(1_799_999_900),
            // Deliberately fake. A well-shaped seal is not evidence of a license.
            "LicenseStateSeal": .string(String(repeating: "a", count: 64)),
        ]
    }

    private func make(
        shared: MigrationRead<[String: MigrationStoredValue]> = .available([:]),
        standard: MigrationRead<[String: MigrationStoredValue]> = .available([:]),
        recaps: MigrationRead<Data> = .absent,
        session: MigrationSessionState = .idle
    ) throws -> MigrationSnapshot {
        try MigrationSnapshotBuilder.make(
            source: source, snapshotID: snapshotID, capturedAt: now,
            sharedValues: shared, standardValues: standard, recapFile: recaps, sessionState: session
        )
    }

    private func roundTrip(_ snapshot: MigrationSnapshot) throws -> MigrationSnapshot {
        try MigrationSnapshotCodec.decode(MigrationSnapshotCodec.encode(snapshot))
    }

    private func assertError<T>(
        _ expected: MigrationSnapshotError, file: StaticString = #filePath, line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? MigrationSnapshotError, expected, file: file, line: line)
        }
    }

    func testAbsentEmptyAndExplicitFalseAreDistinct() throws {
        let absent = try roundTrip(make(shared: .absent, standard: .absent))
        let empty = try roundTrip(make())
        let explicit = try roundTrip(make(shared: .available([
            "CrashReportingEnabled": .bool(false), "LifetimeInterventionCount": .integer(0),
            "LastSeenWhatsNewVersion": .string(""),
        ])))
        XCTAssertNil(absent.sharedPreferences.values)
        XCTAssertNil(absent.standardPreferences.values)
        XCTAssertEqual(empty.sharedPreferences.values, [:])
        XCTAssertEqual(explicit.sharedPreferences.values?["CrashReportingEnabled"], .bool(false))
        XCTAssertEqual(explicit.sharedPreferences.values?["LifetimeInterventionCount"], .integer(0))
        XCTAssertEqual(explicit.sharedPreferences.values?["LastSeenWhatsNewVersion"], .string(""))
        XCTAssertNotEqual(absent, empty)
        XCTAssertEqual(absent.licenseCacheFormat, .absent)
    }

    func testUnavailableSourcesNeverBecomeEmptySnapshots() {
        assertError(.unavailableSource) { try make(shared: .unavailable) }
        assertError(.unavailableSource) { try make(standard: .unavailable) }
        assertError(.unavailableSource) { try make(recaps: .unavailable) }
    }

    func testFourZeroOfflinePaidFixtureRemainsUnsealedAndBlocked() throws {
        let original = legacyPaid
        // This is the pre-seal 4.0.0 policy input, not an upgrade execution test.
        XCTAssertTrue(LicensePolicy.canEnableProtection(
            cachedLicenseValid: true, lastVerifiedAt: Date(timeIntervalSince1970: 1_799_999_400),
            now: now, grandfatherDeadline: nil
        ))
        let snapshot = try roundTrip(make(shared: .available(original)))
        XCTAssertEqual(snapshot.licenseCacheFormat, .legacyUnsealed)
        XCTAssertEqual(snapshot.licenseCache["LicenseLastVerifiedAt"], .real(1_799_999_400))
        XCTAssertEqual(snapshot.licenseCache["LicenseGrandfatherChecked"], .bool(true))
        XCTAssertNil(snapshot.licenseCache["LicenseStateSeal"])
        XCTAssertNil(snapshot.licenseCache["LicenseGrandfatherDeadline"])
        XCTAssertNil(snapshot.licenseCache["LicenseLastSeenAt"])
        XCTAssertEqual(snapshot.sharedPreferences.values?["AWDLMonitoringEnabled"], .bool(true))
        XCTAssertEqual(snapshot.sharedPreferences.values?["CrashReportingEnabled"], .bool(false))
        XCTAssertTrue(snapshot.cutoverReadiness.reasons.contains(.legacyUnsealedLicenseRequiresCompatibilityPath))
        XCTAssertEqual(snapshot.cutoverReadiness.status, .notReady)
        XCTAssertEqual(original, legacyPaid)
    }

    func testSealedCacheIsOnlyStructurallyRecognized() throws {
        let snapshot = try roundTrip(make(shared: .available(sealedCache)))
        XCTAssertEqual(snapshot.licenseCacheFormat, .sealedV1Unverified)
        XCTAssertEqual(snapshot.licenseCache, sealedCache)
        XCTAssertTrue(snapshot.cutoverReadiness.reasons.contains(.licenseSealNotVerified))
        XCTAssertEqual(snapshot.cutoverReadiness.status, .notReady)
    }

    func testMalformedCacheCannotProduceSuccessfulSnapshot() {
        var partial = sealedCache
        partial.removeValue(forKey: "LicenseLastSeenAt")
        XCTAssertEqual(MigrationSnapshotBuilder.classifyLicenseCache(partial), .malformed)
        assertError(.invalidValue) { try make(shared: .available(partial)) }
        partial = sealedCache
        partial["LicenseStateSeal"] = .string("invalid")
        assertError(.invalidValue) { try make(shared: .available(partial)) }
        XCTAssertEqual(MigrationSnapshotBuilder.classifyLicenseCache(["unexpected": .bool(true)]), .malformed)
    }

    func testOriginalDeadlinesClockMarksAndDateValuesAreNeverRefreshed() throws {
        for deadline in [0.0, 1_700_000_000, 1_800_000_100] {
            var cache = sealedCache
            cache["LicenseGrandfatherDeadline"] = .real(deadline)
            cache["LicenseLastSeenAt"] = .real(1_900_000_000) // A future clock mark stays evidence.
            cache["LicenseTransitionLastPresentedAt"] = .dateEpochSeconds(1_799_990_000.25)
            let snapshot = try roundTrip(make(shared: .available(cache)))
            XCTAssertEqual(snapshot.licenseCache["LicenseGrandfatherDeadline"], .real(deadline))
            XCTAssertEqual(snapshot.licenseCache["LicenseLastSeenAt"], .real(1_900_000_000))
            XCTAssertEqual(snapshot.sharedPreferences.values?["LicenseTransitionLastPresentedAt"],
                           .dateEpochSeconds(1_799_990_000.25))
        }
    }

    func testUnknownPreferenceAndWrongValueKindsAreRejectedWithoutLeakingValues() {
        let canary = "synthetic-license-key-never-export"
        do {
            _ = try make(shared: .available(["gumroad-key": .string(canary)]))
            XCTFail("Unknown preference accepted")
        } catch {
            XCTAssertEqual(error as? MigrationSnapshotError, .unknownField)
            XCTAssertFalse(String(describing: error).contains(canary))
        }
        assertError(.unknownField) { try make(standard: .available(["SUFeedURL": .string("https://example.com")])) }
        assertError(.invalidValue) { try make(shared: .available(["CrashReportingEnabled": .integer(0)])) }
        assertError(.invalidValue) { try make(shared: .available(["LifetimeInterventionCount": .integer(-1)])) }
        assertError(.invalidValue) { try make(shared: .available(["ProtectionPauseUntil": .real(.infinity)])) }
        assertError(.invalidValue) { try make(shared: .available(["LicenseTransitionLastPresentedAt": .real(10)])) }
    }

    func testBothVisibilityKeysAndCountersSurviveWithoutRecomputation() throws {
        let values: [String: MigrationStoredValue] = [
            "ControlCenterWidgetEnabled": .bool(false), "ControlCenterOnlyEnabled": .bool(true),
            "BetaChannelEnabled": .bool(true), "CompletedProtectedSessionCount": .integer(600),
            "LifetimeInterventionCount": .integer(900),
        ]
        let snapshot = try roundTrip(make(shared: .available(values)))
        XCTAssertEqual(snapshot.sharedPreferences.values, values)
        XCTAssertEqual(snapshot.completedSessionCount, 0)
    }

    func testHistoricalDashboardIntervalIsPreservedWithAnIssue() throws {
        let snapshot = try roundTrip(make(standard: .available([
            "DashboardSelectedPingTargetID": .string("historical-target"), "DashboardUpdateInterval": .real(3),
        ])))
        XCTAssertEqual(snapshot.standardPreferences.values?["DashboardUpdateInterval"], .real(3))
        XCTAssertEqual(snapshot.validationIssues, [.historicalDashboardInterval])
    }

    private var targetRecord: [String: Any] {
        ["id": "20000000-0000-4000-8000-000000000002", "displayName": "Fixture",
         "host": "example.invalid", "port": 443]
    }

    private var legacyRecapRecord: [String: Any] {
        ["id": "30000000-0000-4000-8000-000000000003",
         "startedAt": "2026-10-01T10:00:00Z", "endedAt": "2026-10-01T10:01:00Z",
         "trigger": "manual", "sampleCount": 10, "successfulSampleCount": 9,
         "medianLatencyMs": 20, "p95LatencyMs": 30, "jitterMs": 2,
         "packetLossPercent": 10, "interventionCount": 1]
    }

    private func blob(_ records: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
    }

    func testNestedJSONBytesAndLegacyRecapsSurviveExactly() throws {
        let targets = try blob([targetRecord]) + Data("\n\n".utf8)
        let recaps = try blob([legacyRecapRecord]) + Data(" \n".utf8)
        let snapshot = try roundTrip(make(
            shared: .available(["DashboardCustomPingTargets": .data(targets)]), recaps: .available(recaps)
        ))
        XCTAssertEqual(snapshot.sharedPreferences.values?["DashboardCustomPingTargets"], .data(targets))
        XCTAssertEqual(snapshot.completedSessions.bytes, recaps)
        XCTAssertEqual(snapshot.completedSessionCount, 1)
        let empty = try roundTrip(make(recaps: .available(Data("[]".utf8))))
        XCTAssertEqual(empty.completedSessions.bytes, Data("[]".utf8))
        XCTAssertNotEqual(empty.completedSessions, MigrationBlob(bytes: nil))
    }

    func testCorruptAndInvalidTargetsFailInsteadOfBecomingEmpty() throws {
        assertError(.malformedBlob) {
            try make(shared: .available(["DashboardCustomPingTargets": .data(Data("broken".utf8))]))
        }
        var bad = targetRecord
        bad["host"] = ""
        assertError(.invalidValue) {
            try make(shared: .available(["DashboardCustomPingTargets": .data(try blob([bad]))]))
        }
        assertError(.duplicateRecordID) {
            try make(shared: .available(["DashboardCustomPingTargets": .data(try blob([targetRecord, targetRecord]))]))
        }
        bad = targetRecord
        bad["unexpected"] = "private-canary"
        assertError(.unknownField) {
            try make(shared: .available(["DashboardCustomPingTargets": .data(try blob([bad]))]))
        }
    }

    func testFourZeroTargetSyntaxIsPreservedWithoutActivation() throws {
        var record = targetRecord
        record["host"] = "https://example.invalid/path"
        let bytes = try blob([record])
        let snapshot = try roundTrip(make(
            shared: .available(["DashboardCustomPingTargets": .data(bytes)])
        ))
        XCTAssertEqual(snapshot.sharedPreferences.values?["DashboardCustomPingTargets"], .data(bytes))
        XCTAssertEqual(snapshot.validationIssues, [.historicalPingTarget])
        XCTAssertEqual(snapshot.cutoverReadiness.status, .notReady)
    }

    func testInvalidRecapsFailWithoutChangingInput() throws {
        var invalid = legacyRecapRecord
        invalid["successfulSampleCount"] = 11
        let original = try blob([invalid])
        assertError(.invalidValue) { try make(recaps: .available(original)) }
        XCTAssertEqual(original, try blob([invalid]))
        invalid = legacyRecapRecord
        invalid["endedAt"] = "2026-09-01T10:01:00Z"
        assertError(.invalidValue) { try make(recaps: .available(try blob([invalid]))) }
        assertError(.duplicateRecordID) { try make(recaps: .available(try blob([legacyRecapRecord, legacyRecapRecord]))) }
        assertError(.malformedBlob) { try make(recaps: .available(Data())) }
    }

    func testModernRecapsAreNotTruncatedToTheLiveStoresFiftyRecordLimit() throws {
        let records = (1...51).map { index -> [String: Any] in
            var record = legacyRecapRecord
            record["id"] = String(format: "30000000-0000-4000-8000-%012d", index)
            record["endReason"] = "protectionPaused"
            record["protectionWasInterrupted"] = true
            return record
        }
        let bytes = try blob(records)
        let snapshot = try roundTrip(make(recaps: .available(bytes)))
        XCTAssertEqual(snapshot.completedSessionCount, 51)
        XCTAssertEqual(snapshot.completedSessions.bytes, bytes)
    }

    func testEverySnapshotRetainsPermanentBlockers() throws {
        for session in [MigrationSessionState.idle, .active, .transitioning] {
            let snapshot = try roundTrip(make(session: session))
            XCTAssertEqual(snapshot.cutoverReadiness.status, .notReady)
            for reason in MigrationCutoverBlocker.permanent { XCTAssertTrue(snapshot.cutoverReadiness.reasons.contains(reason)) }
            XCTAssertEqual(snapshot.cutoverReadiness.reasons.contains(.activeSessionNotFinalized), session != .idle)
        }
    }

    private func alterEnvelope(_ data: Data, _ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutate(&envelope)
        return try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys)
    }

    private func alterPayload(_ data: Data, _ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        try alterEnvelope(data) { envelope in
            let encoded = try XCTUnwrap(envelope["payload"] as? String)
            let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
            var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            try mutate(&payload)
            let changed = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
            envelope["payload"] = changed.base64EncodedString()
            envelope["payloadSHA256"] = SHA256.hash(data: changed).map { String(format: "%02x", $0) }.joined()
        }
    }

    func testDigestTruncationUnknownSchemaAndMalformedBase64AreRejected() throws {
        let encoded = try MigrationSnapshotCodec.encode(make())
        let badDigest = try alterEnvelope(encoded) { $0["payloadSHA256"] = String(repeating: "0", count: 64) }
        assertError(.digestMismatch) { try MigrationSnapshotCodec.decode(badDigest) }
        assertError(.malformedDocument) { try MigrationSnapshotCodec.decode(Data(encoded.dropLast())) }
        let badSchema = try alterEnvelope(encoded) { $0["schemaVersion"] = 2 }
        assertError(.unsupportedSchema) { try MigrationSnapshotCodec.decode(badSchema) }
        let badFormat = try alterEnvelope(encoded) { $0["format"] = "another-product" }
        assertError(.unsupportedFormat) { try MigrationSnapshotCodec.decode(badFormat) }
        let badBase64 = try alterEnvelope(encoded) { $0["payload"] = "!not-base64!" }
        assertError(.malformedDocument) { try MigrationSnapshotCodec.decode(badBase64) }
    }

    func testUnknownEnvelopePayloadAndValueFieldsAreRejected() throws {
        let encoded = try MigrationSnapshotCodec.encode(make(shared: .available(["CrashReportingEnabled": .bool(false)])))
        let envelope = try alterEnvelope(encoded) { $0["unknown"] = true }
        assertError(.unknownField) { try MigrationSnapshotCodec.decode(envelope) }
        let payload = try alterPayload(encoded) { $0["unknown"] = true }
        assertError(.unknownField) { try MigrationSnapshotCodec.decode(payload) }
        let nested = try alterPayload(encoded) { payload in
            var domain = try XCTUnwrap(payload["sharedPreferences"] as? [String: Any])
            var values = try XCTUnwrap(domain["values"] as? [String: Any])
            var value = try XCTUnwrap(values["CrashReportingEnabled"] as? [String: Any])
            value["unknown"] = true
            values["CrashReportingEnabled"] = value
            domain["values"] = values
            payload["sharedPreferences"] = domain
        }
        assertError(.unknownField) { try MigrationSnapshotCodec.decode(nested) }
    }

    func testRecomputedDigestCannotRemoveBlockersOrForgeDerivedMetadata() throws {
        let encoded = try MigrationSnapshotCodec.encode(make())
        let unblocked = try alterPayload(encoded) {
            $0["cutoverReadiness"] = ["status": "notReady", "reasons": []]
        }
        assertError(.inconsistentMetadata) { try MigrationSnapshotCodec.decode(unblocked) }
        let falseCount = try alterPayload(encoded) { $0["completedSessionCount"] = 20 }
        assertError(.inconsistentMetadata) { try MigrationSnapshotCodec.decode(falseCount) }
        let falseFormat = try alterPayload(encoded) { $0["licenseCacheFormat"] = "sealedV1Unverified" }
        assertError(.inconsistentMetadata) { try MigrationSnapshotCodec.decode(falseFormat) }
        let ready = try alterPayload(encoded) {
            $0["cutoverReadiness"] = ["status": "ready", "reasons": []]
        }
        assertError(.malformedDocument) { try MigrationSnapshotCodec.decode(ready) }
    }

    func testOversizedInputsFailBeforeJSONParsing() {
        let oversized = Data(repeating: 0, count: MigrationSnapshotCodec.maximumEnvelopeBytes + 1)
        assertError(.sizeLimitExceeded) { try MigrationSnapshotCodec.decode(oversized) }
        let blob = Data(repeating: 0, count: MigrationSnapshotBuilder.maximumPayloadBytes + 1)
        assertError(.sizeLimitExceeded) { try make(recaps: .available(blob)) }
        let text = String(repeating: "x", count: MigrationSnapshotBuilder.maximumStringBytes + 1)
        assertError(.sizeLimitExceeded) { try make(standard: .available(["DashboardSelectedPingTargetID": .string(text)])) }
    }

    func testEncodingIsDeterministicForFixedInputs() throws {
        let snapshot = try make(shared: .available(legacyPaid))
        let first = try MigrationSnapshotCodec.encode(snapshot)
        XCTAssertEqual(first, try MigrationSnapshotCodec.encode(snapshot))
        XCTAssertEqual(first, try MigrationSnapshotCodec.encode(MigrationSnapshotCodec.decode(first)))
        let later = try MigrationSnapshotBuilder.make(
            source: source, snapshotID: snapshotID, capturedAt: now.addingTimeInterval(1),
            sharedValues: .available(legacyPaid), standardValues: .available([:]),
            recapFile: .absent, sessionState: .idle
        )
        XCTAssertNotEqual(first, try MigrationSnapshotCodec.encode(later))
    }
}

#endif
