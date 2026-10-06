import CoreFoundation
import Foundation

enum CaptureProjection {
    static var sharedKinds: [String: MigrationSnapshotBuilder.ValueKind] {
        MigrationSnapshotBuilder.sharedKinds.merging(MigrationSnapshotBuilder.licenseKinds) { first, _ in first }
    }

    static func preferences(_ file: CapturedFile, standard: Bool) throws -> MigrationRead<[String: MigrationStoredValue]> {
        guard let bytes = file.bytes else { return .absent }
        let plist: Any
        do { plist = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) }
        catch { throw CaptureFailure.unsupportedStore(standard ? "standard" : "shared") }
        guard let domain = plist as? [String: Any] else {
            throw CaptureFailure.unsupportedStore(standard ? "standard" : "shared")
        }
        // Both preferences and licensing can fall back to standard defaults.
        // The current snapshot cannot represent that provenance or precedence.
        if standard, domain.keys.contains(where: { sharedKinds[$0] != nil }) {
            throw CaptureFailure.ambiguousStandardFallback
        }
        let kinds = standard ? MigrationSnapshotBuilder.standardKinds : sharedKinds
        var values: [String: MigrationStoredValue] = [:]
        for (key, kind) in kinds {
            guard let value = domain[key] else { continue }
            values[key] = try stored(value, kind: kind)
        }
        // Unrelated OS/updater keys are deliberately not exported. Unknown
        // keys inside the snapshot and nested JSON remain builder/codec errors.
        return .available(values)
    }

    private static func stored(_ value: Any, kind: MigrationSnapshotBuilder.ValueKind) throws -> MigrationStoredValue {
        switch kind {
        case .bool:
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw CaptureFailure.unsupportedPreferenceType
            }
            return .bool(number.boolValue)
        case .count:
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType)),
                  let integer = Int64(number.stringValue), integer >= 0 else {
                throw CaptureFailure.unsupportedPreferenceType
            }
            return .integer(integer)
        case .real:
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  ["f", "d"].contains(String(cString: number.objCType)), number.doubleValue.isFinite else {
                throw CaptureFailure.unsupportedPreferenceType
            }
            return .real(number.doubleValue)
        case .string:
            guard let string = value as? String else { throw CaptureFailure.unsupportedPreferenceType }
            return .string(string)
        case .date:
            guard let date = value as? Date, date.timeIntervalSince1970.isFinite else {
                throw CaptureFailure.unsupportedPreferenceType
            }
            return .dateEpochSeconds(date.timeIntervalSince1970)
        case .data:
            guard let data = value as? Data else { throw CaptureFailure.unsupportedPreferenceType }
            return .data(data)
        }
    }
}
