#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// Persist this ticket before the first destination operation. Retry with the
/// same ticket AND exact original envelope. It is ownership, not authorization.
struct MigrationImportTicket: Codable, Equatable, Sendable {
    let transactionID: UUID
    let ownerToken: UUID
    let snapshotID: UUID
    let envelopeSHA256: String
}

struct MigrationImportPlan: Sendable {
    let ticket: MigrationImportTicket
    let snapshot: MigrationSnapshot
    fileprivate let envelope: Data

    init(envelope: Data, transactionID: UUID, ownerToken: UUID) throws {
        let snapshot = try MigrationSnapshotCodec.decode(envelope)
        guard snapshot.cutoverReadiness.status == .notReady,
              MigrationCutoverBlocker.permanent.allSatisfy({ snapshot.cutoverReadiness.reasons.contains($0) }) else {
            throw MigrationImportError.invalidSnapshot
        }
        self.envelope = envelope
        self.snapshot = snapshot
        ticket = MigrationImportTicket(transactionID: transactionID, ownerToken: ownerToken,
            snapshotID: snapshot.snapshotID, envelopeSHA256: Self.digest(envelope))
    }

    fileprivate static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Revision comes from persistence and must change on EVERY mutation, including
/// a change later restored to identical bytes. The adapter must never reuse it.
struct MigrationImportVersion: Equatable, Sendable {
    let revision: UUID
    let bytes: Data
}

enum MigrationImportWriteResult {
    case applied
    case conflict
    /// The adapter established that no mutation occurred.
    case unavailable
    /// A mutation may have occurred. Retry by observing the same transaction.
    case outcomeUnknown
}

/// A dedicated staging namespace only, never production defaults or app files.
/// Read and compare-and-swap must be linearizable across processes. Replacement
/// is one durable atomic record, including its manifest and exact envelope.
/// nil expected means create only if absent. Otherwise compare BOTH revision
/// and bytes. Conflicts never mutate. Finish recovery before serving reads.
/// No operation may continue applying writes asynchronously after returning.
/// Never report denied, corrupt or partially readable storage as absent.
/// Bound each record read to maximumRecordBytes before allocating its contents.
protocol MigrationImportPersistence: AnyObject {
    func read(transactionID: UUID) -> MigrationRead<MigrationImportVersion>
    func compareAndSwap(transactionID: UUID, expected: MigrationImportVersion?,
                        replacement: Data) -> MigrationImportWriteResult
}

enum MigrationImportError: Error, Equatable {
    case invalidSnapshot
    case invalidStagingRecord
    case ownershipOrContentConflict
    case transactionRolledBack
    case destinationUnavailable
    case destinationChanged
    case writeOutcomeUnknown
    case readbackMismatch
}

struct MigrationImportReceipt: Equatable, Sendable {
    enum State: String, Sendable {
        case stagedAwaitingContinuity
        case rolledBack
        case nothingStaged
    }
    let ticket: MigrationImportTicket
    let state: State
    /// Copied from the validated source snapshot, without removing any gate.
    let cutoverReadiness: MigrationCutoverReadiness
    let retainsOriginalInstallation = true
}

/// Stages an import candidate. There is deliberately no activation/commit API.
/// No I/O occurs until an explicit injected persistence method is called.
/// Any thrown error can follow an earlier committed phase. Always recover with
/// the retained plan and original transaction, never assume an error means absent.
struct MigrationImportCoordinator<Store: MigrationImportPersistence> {
    // A 16 MiB snapshot envelope expands to about 22 MiB as JSON Data, with
    // bounded UUID/hash metadata. Adapters must impose this bound before reads.
    static var maximumRecordBytes: Int { 24 * 1024 * 1024 }
    let persistence: Store

    private enum Phase: String, Codable { case preparing, stagedAwaitingContinuity, rolledBack }
    private struct Record: Codable {
        let formatVersion: Int
        let ticket: MigrationImportTicket
        let phase: Phase
        let envelope: Data?
    }

    /// May leave a prepared record after an interruption or uncertain write.
    /// Repeating this method with the same plan resumes that record safely.
    func stage(_ plan: MigrationImportPlan) throws -> MigrationImportReceipt {
        let version: MigrationImportVersion
        switch persistence.read(transactionID: plan.ticket.transactionID) {
        case .unavailable: throw MigrationImportError.destinationUnavailable
        case .absent:
            version = try replace(plan, expected: nil, phase: .preparing)
        case .available(let observed):
            version = observed
        }
        switch try validatedPhase(version, plan: plan) {
        case .rolledBack: throw MigrationImportError.transactionRolledBack
        case .stagedAwaitingContinuity:
            return receipt(plan, state: .stagedAwaitingContinuity)
        case .preparing:
            _ = try replace(plan, expected: version, phase: .stagedAwaitingContinuity)
            return receipt(plan, state: .stagedAwaitingContinuity)
        }
    }

    /// Removes payload only by conditional replacement of an unchanged owned
    /// record. A tombstone retains identity so retries cannot resurrect it.
    /// Never deletes source data, another transaction, or an edited record.
    func rollback(_ plan: MigrationImportPlan) throws -> MigrationImportReceipt {
        switch persistence.read(transactionID: plan.ticket.transactionID) {
        case .unavailable: throw MigrationImportError.destinationUnavailable
        case .absent:
            return receipt(plan, state: .nothingStaged)
        case .available(let version):
            switch try validatedPhase(version, plan: plan) {
            case .rolledBack: return receipt(plan, state: .rolledBack)
            case .preparing, .stagedAwaitingContinuity:
                _ = try replace(plan, expected: version, phase: .rolledBack)
                return receipt(plan, state: .rolledBack)
            }
        }
    }

    private func receipt(_ plan: MigrationImportPlan, state: MigrationImportReceipt.State) -> MigrationImportReceipt {
        MigrationImportReceipt(ticket: plan.ticket, state: state,
            cutoverReadiness: plan.snapshot.cutoverReadiness)
    }

    private func replace(_ plan: MigrationImportPlan, expected: MigrationImportVersion?,
                         phase: Phase) throws -> MigrationImportVersion {
        let record = Record(formatVersion: 1, ticket: plan.ticket, phase: phase,
            envelope: phase == .rolledBack ? nil : plan.envelope)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes: Data
        do { bytes = try encoder.encode(record) }
        catch { throw MigrationImportError.invalidStagingRecord }
        guard bytes.count <= Self.maximumRecordBytes else { throw MigrationImportError.invalidStagingRecord }

        switch persistence.compareAndSwap(transactionID: plan.ticket.transactionID,
                                          expected: expected, replacement: bytes) {
        case .applied: break
        case .conflict: throw MigrationImportError.destinationChanged
        case .unavailable: throw MigrationImportError.destinationUnavailable
        case .outcomeUnknown: throw MigrationImportError.writeOutcomeUnknown
        }
        // The adapter's success alone never counts as a verified stage.
        switch persistence.read(transactionID: plan.ticket.transactionID) {
        case .unavailable: throw MigrationImportError.destinationUnavailable
        case .absent: throw MigrationImportError.readbackMismatch
        case .available(let observed):
            guard observed.bytes == bytes,
                  expected == nil || observed.revision != expected?.revision,
                  try validatedPhase(observed, plan: plan) == phase else {
                throw MigrationImportError.readbackMismatch
            }
            return observed
        }
    }

    private func validatedPhase(_ version: MigrationImportVersion, plan: MigrationImportPlan) throws -> Phase {
        guard version.bytes.count <= Self.maximumRecordBytes else { throw MigrationImportError.invalidStagingRecord }
        let record: Record
        do {
            guard let root = try JSONSerialization.jsonObject(with: version.bytes) as? [String: Any],
                  Set(root.keys).isSubset(of: ["formatVersion", "ticket", "phase", "envelope"]),
                  let ticket = root["ticket"] as? [String: Any],
                  Set(ticket.keys) == Set(["transactionID", "ownerToken", "snapshotID", "envelopeSHA256"]) else {
                throw MigrationImportError.invalidStagingRecord
            }
            record = try JSONDecoder().decode(Record.self, from: version.bytes)
        } catch {
            // Never expose decoder errors containing stored values or bytes.
            throw MigrationImportError.invalidStagingRecord
        }
        guard record.formatVersion == 1 else { throw MigrationImportError.invalidStagingRecord }
        guard record.ticket == plan.ticket else { throw MigrationImportError.ownershipOrContentConflict }
        if record.phase == .rolledBack {
            guard record.envelope == nil else { throw MigrationImportError.invalidStagingRecord }
        } else {
            guard record.envelope == plan.envelope else { throw MigrationImportError.ownershipOrContentConflict }
            // Exact byte equality preserves absence, false/zero, date values,
            // nested blob bytes and cached claims. Decode rechecks every gate.
            guard let envelope = record.envelope,
                  (try? MigrationSnapshotCodec.decode(envelope)) == plan.snapshot else {
                throw MigrationImportError.invalidStagingRecord
            }
        }
        return record.phase
    }
}
#endif
