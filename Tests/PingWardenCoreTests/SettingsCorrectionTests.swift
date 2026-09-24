import XCTest
@testable import PingWardenCore

final class SettingsCorrectionTests: XCTestCase {
    func testRejectsURLsAndNonHostInputWithoutTouchingStoredTargets() {
        let suite = "PingWarden.SettingsCorrectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomPingTargetStore(userDefaults: defaults)
        let original = CustomPingTarget(displayName: "Existing", host: "localhost", port: 53)
        store.add(original)
        for host in ["https://example.com/path", "example.com/path", "example.com:443",
                     "user@example.com", "example.com?x=1", "example.com#x", "bad host",
                     "[::1]", "::1%", "::xyz", ".", "a..b", "a\n.example"] {
            XCTAssertEqual(CustomPingTargetStore.validate(displayName: "New", host: host, port: 53), .hostInvalid, host)
        }
        XCTAssertEqual(store.load(), [original])
    }

    func testPreservesIPv4IPv6DNSAndLocalHostnames() {
        for host in ["127.0.0.1", "::1", "2001:db8::1234", "::ffff:192.0.2.1",
                     "fe80::1%en0", "fe80::1%3", "localhost", "my-mac.local",
                     "example.com.", "xn--bcher-kva.example", "bücher.example"] {
            XCTAssertNil(CustomPingTargetStore.validate(displayName: "New", host: host, port: 65535), host)
        }
    }

    func testReminderCopyOnlyPromisesFutureThresholds() {
        let intro = LicenseReminderPolicy.followUpMessage(daysRemaining: 90)
        XCTAssertTrue(intro.contains("30 days and 7 days"))
        for remaining in [30, 29, 8] {
            let message = LicenseReminderPolicy.followUpMessage(daysRemaining: remaining)
            XCTAssertFalse(message.contains("30 days"))
            XCTAssertTrue(message.contains("again when 7 days"))
        }
        for remaining in [7, 6, 1, 0] {
            let message = LicenseReminderPolicy.followUpMessage(daysRemaining: remaining)
            XCTAssertTrue(message.contains("final"))
            XCTAssertFalse(message.contains("again"))
        }
    }
}
