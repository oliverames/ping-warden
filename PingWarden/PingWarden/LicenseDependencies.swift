import Foundation
import Security

/// The manager still chooses the same keys and defaults semantics. Fixtures
/// supply memory storage without constructing a UserDefaults domain.
protocol LicenseStateStore: AnyObject {
    func bool(forKey key: String) -> Bool
    func double(forKey key: String) -> Double
    func string(forKey key: String) -> String?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: LicenseStateStore {}

enum LicenseCredentialFailure: Equatable {
    case interactionNotAllowed
    case userCanceled
    case authenticationFailed
    case unavailable(OSStatus)
    case malformedValue
}

enum LicenseCredentialRead {
    /// A marker lookup deliberately requests no secret data.
    case found(Data?)
    case notFound
    case blocked(LicenseCredentialFailure)
}

struct LicenseCredentialClient {
    let read: (_ service: String, _ account: String, _ returnData: Bool) -> LicenseCredentialRead
    let update: (_ service: String, _ account: String, _ data: Data) -> OSStatus
    let add: (_ service: String, _ account: String, _ data: Data) -> OSStatus
    let delete: (_ service: String, _ account: String) -> OSStatus
}

struct LicenseSealClient {
    let deviceIdentifier: () -> String
    let matches: (_ stored: String?, _ payload: String) -> Bool
    let seal: (_ payload: String) -> String
}

struct LicenseDependencies {
    let defaults: any LicenseStateStore
    let now: () -> Date
    let seal: LicenseSealClient
    let credentials: LicenseCredentialClient
    let verify: @MainActor (_ key: String) async -> Result<Data, Error>
}

// MARK: - Live adapters
// The isolated harness omits this section and supplies trapping live factories.
// It compiles the manager's real decisions against explicit fixture dependencies.

extension LicenseSealClient {
    static var live: LicenseSealClient {
        LicenseSealClient(
            deviceIdentifier: { LicenseStateSeal.deviceIdentifier() },
            matches: { LicenseStateSeal.matches($0, payload: $1) },
            seal: { LicenseStateSeal.seal($0) }
        )
    }
}

extension LicenseCredentialClient {
    static var live: LicenseCredentialClient {
        LicenseCredentialClient(
            read: { service, account, returnData in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecReturnData as String: returnData,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                var item: CFTypeRef?
                let status: OSStatus
                if returnData {
                    status = SecItemCopyMatching(query as CFDictionary, &item)
                } else {
                    status = SecItemCopyMatching(query as CFDictionary, nil)
                }
                switch status {
                case errSecSuccess:
                    guard returnData else { return .found(nil) }
                    guard let data = item as? Data else { return .blocked(.malformedValue) }
                    return .found(data)
                case errSecItemNotFound:
                    return .notFound
                case errSecInteractionNotAllowed:
                    return .blocked(.interactionNotAllowed)
                case errSecUserCanceled:
                    return .blocked(.userCanceled)
                case errSecAuthFailed:
                    return .blocked(.authenticationFailed)
                default:
                    return .blocked(.unavailable(status))
                }
            },
            update: { service, account, data in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                ]
                return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            },
            add: { service, account, data in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]
                return SecItemAdd(query as CFDictionary, nil)
            },
            delete: { service, account in
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                ]
                return SecItemDelete(query as CFDictionary)
            }
        )
    }
}
