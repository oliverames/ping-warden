import Darwin
import Foundation

/// Only fixed labels and operating-system status codes reach stderr.
enum CaptureFailure: Error {
    case invalidArguments, invalidSourceApplication, unsupportedPreferenceType
    case ambiguousStandardFallback, sourceChanged, inconsistentSnapshot
    case signature(Int32), unavailable(String, Int32), unsupportedStore(String), sizeLimit(String)

    var diagnostic: String {
        switch self {
        case .invalidArguments: return "invalidArguments"
        case .invalidSourceApplication: return "invalidSourceApplication"
        case .unsupportedPreferenceType: return "unsupportedPreferenceType"
        case .ambiguousStandardFallback: return "ambiguousStandardFallback"
        case .sourceChanged: return "sourceChanged"
        case .inconsistentSnapshot: return "inconsistentSnapshot"
        case .signature(let code): return "signatureUnavailable(\(code))"
        case .unavailable(let store, let code): return "unavailable(\(store),\(code))"
        case .unsupportedStore(let store): return "unsupportedStore(\(store))"
        case .sizeLimit(let store): return "sizeLimit(\(store))"
        }
    }
}

private struct CaptureArguments {
    let sourceApp: URL
    let output: URL
    let stores: [CaptureStorePath]

    init(_ arguments: [String]) throws {
        guard getuid() != 0, getuid() == geteuid(), getgid() == getegid(),
              arguments.count == 10, let account = getpwuid(getuid()), let homePointer = account.pointee.pw_dir else {
            throw CaptureFailure.invalidArguments
        }
        let allowed = Set(["--source-app", "--shared-preferences", "--standard-preferences", "--recaps", "--output"])
        var urls: [String: URL] = [:]
        for offset in stride(from: 0, to: arguments.count, by: 2) {
            let option = arguments[offset]
            let raw = arguments[offset + 1]
            guard allowed.contains(option), urls[option] == nil, raw.hasPrefix("/"), !raw.utf8.contains(0),
                  !raw.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                  !raw.split(separator: "/", omittingEmptySubsequences: false).contains(".") else {
                throw CaptureFailure.invalidArguments
            }
            let url = URL(fileURLWithPath: raw)
            guard url.standardizedFileURL.path == raw else { throw CaptureFailure.invalidArguments }
            urls[option] = url
        }
        guard let sourceApp = urls["--source-app"], let output = urls["--output"] else {
            throw CaptureFailure.invalidArguments
        }
        let home = URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        stores = [
            CaptureStorePath(label: "shared", root: library.appendingPathComponent("Group Containers/\(CaptureIdentity.group)", isDirectory: true),
                components: ["Library", "Preferences", "\(CaptureIdentity.group).plist"]),
            CaptureStorePath(label: "standard", root: library.appendingPathComponent("Preferences", isDirectory: true),
                components: ["\(CaptureIdentity.sourceIdentifier).plist"]),
            CaptureStorePath(label: "recaps", root: library.appendingPathComponent("Application Support", isDirectory: true),
                components: ["Ping Warden", "protected-sessions.json"]),
        ]
        for (option, store) in zip(["--shared-preferences", "--standard-preferences", "--recaps"], stores) {
            guard urls[option]?.path == store.url.path else { throw CaptureFailure.invalidArguments }
        }
        // No capture artifact can be created within an input store or app.
        for root in stores.map(\.root) + [sourceApp, Bundle.main.bundleURL] {
            guard output.path != root.path, !output.path.hasPrefix(root.path + "/") else {
                throw CaptureFailure.invalidArguments
            }
        }
        self.sourceApp = sourceApp
        self.output = output
    }
}

private struct CaptureReport: Encodable {
    struct Store: Encodable {
        let label: String
        let path: String
        let presence: String
        let byteCount: Int?
        let sha256: String?
        let token: CaptureFileToken?
    }

    struct License: Encodable {
        let cache: String
        let clock: String
        let paidWindowClaim: String
        let transitionWindowClaim: String
        let originalOfflineExpiryEpochSeconds: Double?
        let originalTransitionDeadlineEpochSeconds: Double?
        let unresolvedReasons: [String]
        let credential = "notObserved"
        let grandfatherMarker = "notObserved"
        let legacyMigrationMarker = "notObserved"
        let deviceIdentifier = "unavailable"
        let verification = "notRequested"
        let helper = "notObserved"
        let sealedPolicy = "notEstablished"
        let disposition = "retainOriginalInstallation"
    }

    let reportFormat = "com.amesvt.pingwarden.persisted-capture-report"
    let reportVersion = 1
    let snapshotID: UUID
    let snapshotSHA256: String
    let captureStartedAtEpochSeconds: Double
    let captureFinishedAtEpochSeconds: Double
    let sourceAppPath: String
    let sourceApp: CaptureIdentity.Observation
    let captureTool: CaptureIdentity.Observation
    let stores: [Store]
    let license: License
    let cutoverReadiness: MigrationCutoverReadiness
    let persistedReadPassesMatched = true
    let atomicCapture = false
    let sourceWriterUnobserved = true
    let sourceVersionIsObservedBundleMetadataOnly = true
    let sourceMayHaveUnflushedPreferences = true
    let sessionState = "unobserved"
}

@main
enum PingWardenCapture {
    static func main() {
        do {
            try capture(CaptureArguments(Array(CommandLine.arguments.dropFirst())))
            print("Persisted snapshot created. Migration remains notReady. Retain the original installation.")
        } catch let error as CaptureFailure {
            fail(error.diagnostic)
        } catch let error as MigrationSnapshotError {
            fail("snapshotRejected(\(error))")
        } catch {
            fail("captureFailed")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Capture failed: \(message). No app state was changed.\n".utf8))
        exit(EXIT_FAILURE)
    }

    private static func capture(_ arguments: CaptureArguments) throws {
        let started = Date()
        let tool = try CaptureIdentity.inspect(Bundle.main.bundleURL, identifier: CaptureIdentity.captureIdentifier)
        let source = try CaptureIdentity.inspect(arguments.sourceApp, identifier: CaptureIdentity.sourceIdentifier)
        guard let metadata = source.source else { throw CaptureFailure.invalidSourceApplication }
        let first = try arguments.stores.map(CaptureFileIO.read)
        let second = try arguments.stores.map(CaptureFileIO.read)
        guard first == second else { throw CaptureFailure.sourceChanged }
        // Also reject a selected source bundle replaced during capture. The
        // selected app is still not proof of which version last wrote a store.
        guard try source == CaptureIdentity.inspect(arguments.sourceApp, identifier: CaptureIdentity.sourceIdentifier) else {
            throw CaptureFailure.sourceChanged
        }
        let observedAt = Date()
        let shared = try CaptureProjection.preferences(second[0], standard: false)
        let standard = try CaptureProjection.preferences(second[1], standard: true)
        let snapshot = try MigrationSnapshotBuilder.make(source: metadata, snapshotID: UUID(), capturedAt: observedAt,
            sharedValues: shared, standardValues: standard, recapFile: second[2].migrationRead, sessionState: .unobserved)
        let assessment = LicenseContinuityAssessment.assess(.init(
            cache: .available(snapshot.licenseCache), observedAt: observedAt, deviceIdentifier: .unavailable,
            credential: nil, grandfatherMarker: nil, legacyMigrationMarker: nil,
            helperEnabled: nil, verification: .notRequested), matchesSeal: { _, _ in false })
        guard assessment.sealedPolicy == .notEstablished,
              snapshot.cutoverReadiness.status == .notReady,
              MigrationCutoverBlocker.permanent.allSatisfy({ snapshot.cutoverReadiness.reasons.contains($0) }) else {
            throw CaptureFailure.inconsistentSnapshot
        }
        let encoded = try MigrationSnapshotCodec.encode(snapshot)
        guard try MigrationSnapshotCodec.decode(encoded) == snapshot else { throw CaptureFailure.inconsistentSnapshot }
        let report = CaptureReport(snapshotID: snapshot.snapshotID, snapshotSHA256: CaptureFileIO.digest(encoded),
            captureStartedAtEpochSeconds: started.timeIntervalSince1970,
            captureFinishedAtEpochSeconds: Date().timeIntervalSince1970,
            sourceAppPath: arguments.sourceApp.path, sourceApp: source, captureTool: tool,
            stores: zip(arguments.stores, second).map { path, file in
                CaptureReport.Store(label: path.label, path: path.url.path,
                    presence: file.bytes == nil ? "absent" : "available",
                    byteCount: file.bytes?.count, sha256: file.digest, token: file.token)
            }, license: CaptureReport.License(cache: String(describing: assessment.cache),
                clock: String(describing: assessment.clock), paidWindowClaim: String(describing: assessment.paidWindow),
                transitionWindowClaim: String(describing: assessment.transitionWindow),
                originalOfflineExpiryEpochSeconds: assessment.originalOfflineExpiry?.timeIntervalSince1970,
                originalTransitionDeadlineEpochSeconds: assessment.originalTransitionDeadline?.timeIntervalSince1970,
                unresolvedReasons: assessment.unresolvedReasons.map { String(describing: $0) }),
            cutoverReadiness: snapshot.cutoverReadiness)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportBytes = try encoder.encode(report)
        try CaptureFileIO.write(snapshot: encoded, report: reportBytes, to: arguments.output,
            excluding: arguments.stores.map(\.root) + [arguments.sourceApp, Bundle.main.bundleURL])
    }
}
