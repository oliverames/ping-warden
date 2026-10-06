import CryptoKit
import Foundation
import Security

// Accidental production factory use must fail before accessing a system store.
extension LicenseSealClient {
    static var live: LicenseSealClient { fatalError("Live seal factory is forbidden in license fixtures") }
}

extension LicenseCredentialClient {
    static var live: LicenseCredentialClient { fatalError("Live credential factory is forbidden in license fixtures") }
}

final class MemoryLicenseStore: LicenseStateStore {
    var values: [String: Any]
    var writes: [String] = []

    init(_ values: [String: Any] = [:]) { self.values = values }
    func bool(forKey key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    func double(forKey key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        writes.append("set:" + key)
        values[key] = value
    }
    func removeObject(forKey key: String) {
        writes.append("remove:" + key)
        values.removeValue(forKey: key)
    }
}

final class FixtureClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class FixtureSeal {
    var device = "SYNTHETIC-DEVICE-A"

    // A public test key, unrelated to the app's production seal key.
    static func make(_ payload: String) -> String {
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        return HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
    }

    var client: LicenseSealClient {
        LicenseSealClient(
            deviceIdentifier: { self.device },
            matches: { stored, payload in stored == Self.make(payload) },
            seal: Self.make
        )
    }
}

final class FixtureCredentials {
    var items: [String: Data] = [:]
    var readOverrides: [String: LicenseCredentialRead] = [:]
    var updateStatus: OSStatus?
    var addStatus: OSStatus?
    var events: [String] = []

    private func checkService(_ service: String) {
        precondition(service == "com.amesvt.pingwarden.license", "Unexpected credential service")
    }

    var client: LicenseCredentialClient {
        LicenseCredentialClient(
            read: { service, account, returnData in
                self.checkService(service)
                self.events.append("read:" + account + (returnData ? ":data" : ":marker"))
                if let result = self.readOverrides[account] { return result }
                guard let data = self.items[account] else { return .notFound }
                return .found(returnData ? data : nil)
            },
            update: { service, account, data in
                self.checkService(service)
                self.events.append("update:" + account)
                let status = self.updateStatus ?? (self.items[account] == nil ? errSecItemNotFound : errSecSuccess)
                if status == errSecSuccess { self.items[account] = data }
                return status
            },
            add: { service, account, data in
                self.checkService(service)
                self.events.append("add:" + account)
                let status = self.addStatus ?? (self.items[account] == nil ? errSecSuccess : errSecDuplicateItem)
                if status == errSecSuccess { self.items[account] = data }
                return status
            },
            delete: { service, account in
                self.checkService(service)
                self.events.append("delete:" + account)
                return self.items.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
            }
        )
    }
}

@MainActor
final class FixtureVerifier {
    var result: Result<Data, Error> = .failure(URLError(.notConnectedToInternet))
    var holdReply = false
    private(set) var calls = 0
    private(set) var receivedNormalizedKey = true
    private var reply: CheckedContinuation<Result<Data, Error>, Never>?
    private var callWaiters: [CheckedContinuation<Void, Never>] = []

    func request(_ key: String) async -> Result<Data, Error> {
        calls += 1
        receivedNormalizedKey = receivedNormalizedKey && key == "FIXTURE-LICENSE"
        let waiters = callWaiters
        callWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard holdReply else { return result }
        return await withCheckedContinuation { continuation in
            precondition(reply == nil, "Only one verification may be in flight")
            reply = continuation
        }
    }

    func waitForCall() async {
        if calls > 0 { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func finish() {
        guard let reply else { fatalError("No pending synthetic verification") }
        self.reply = nil
        reply.resume(returning: result)
    }
}

@MainActor
final class LicenseFixture {
    let store: MemoryLicenseStore
    let clock: FixtureClock
    let seal: FixtureSeal
    let credentials: FixtureCredentials
    let verifier: FixtureVerifier
    let manager: LicenseManager

    init(_ values: [String: Any] = [:]) {
        let store = MemoryLicenseStore(values)
        let clock = FixtureClock()
        let seal = FixtureSeal()
        let credentials = FixtureCredentials()
        let verifier = FixtureVerifier()
        self.store = store
        self.clock = clock
        self.seal = seal
        self.credentials = credentials
        self.verifier = verifier
        manager = LicenseManager(dependencies: LicenseDependencies(
            defaults: store,
            now: { clock.now },
            seal: seal.client,
            credentials: credentials.client,
            verify: { key in await verifier.request(key) }
        ))
    }

    func installSyntheticKeyAndMarkers() {
        credentials.items["gumroad-key"] = Data("FIXTURE-LICENSE".utf8)
        credentials.items["grandfather-checked"] = Data("1".utf8)
        credentials.items["legacy-transition-migrated"] = Data("1".utf8)
    }

    func seedSealed(cachedValid: Bool = true, verified: Double? = nil,
                    grandfather: Double = 0, seen: Double? = nil) {
        let verified = verified ?? clock.now.timeIntervalSince1970 - 600
        let seen = seen ?? clock.now.timeIntervalSince1970 - 300
        store.values["LicenseCachedValid"] = cachedValid
        store.values["LicenseLastVerifiedAt"] = verified
        store.values["LicenseGrandfatherDeadline"] = grandfather
        store.values["LicenseLastSeenAt"] = seen
        let payload = LicensePolicy.sealPayload(
            cachedLicenseValid: cachedValid,
            lastVerifiedAt: verified > 0 ? Date(timeIntervalSince1970: verified) : nil,
            grandfatherDeadline: grandfather > 0 ? Date(timeIntervalSince1970: grandfather) : nil,
            lastSeenAt: seen > 0 ? Date(timeIntervalSince1970: seen) : nil,
            deviceIdentifier: seal.device
        )
        store.values["LicenseStateSeal"] = FixtureSeal.make(payload)
    }
}
