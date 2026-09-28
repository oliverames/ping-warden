import Foundation
import XCTest
@testable import PingWardenCore

final class ControlCenterLaunchHandoffTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suite = NSTemporaryDirectory() + "pingwarden-launch-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testFreshHintSilencesOnlyOneLaunch() {
        ControlCenterLaunchHandoff.begin(in: defaults, now: now)
        let first = LaunchSignals(launchedByControlCenter: ControlCenterLaunchHandoff.consume(in: defaults, now: now))
        XCTAssertEqual(InterfaceVisibilityPolicy.launchReason(from: first), .controlCenter)
        let next = LaunchSignals(launchedByControlCenter: ControlCenterLaunchHandoff.consume(in: defaults, now: now))
        XCTAssertEqual(InterfaceVisibilityPolicy.launchReason(from: next), .direct)
        XCTAssertTrue(InterfaceVisibilityPolicy.shouldOpenSettingsAtLaunch(
            mode: .controlCenterOnly, controlCenterAvailable: true,
            showDockIconPreference: false, launchReason: .direct,
            welcomeVisible: false, licenseNoticeVisible: false))
    }

    func testAbandonedAndFutureHintsAreRemoved() {
        for timestamp in [now.addingTimeInterval(-61), now.addingTimeInterval(1)] {
            ControlCenterLaunchHandoff.begin(in: defaults, now: timestamp)
            XCTAssertFalse(ControlCenterLaunchHandoff.consume(in: defaults, now: now))
            XCTAssertNil(defaults.object(forKey: ControlCenterLaunchHandoff.key))
        }
    }

    func testMalformedHintsAreRemoved() {
        for marker: Any in ["bad", ["token": "invalid", "createdAt": now], ["token": UUID().uuidString]] {
            defaults.set(marker, forKey: ControlCenterLaunchHandoff.key)
            XCTAssertFalse(ControlCenterLaunchHandoff.consume(in: defaults, now: now))
            XCTAssertNil(defaults.object(forKey: ControlCenterLaunchHandoff.key))
        }
    }

    func testFailedRequestCannotEraseANewerRequest() {
        let earlier = ControlCenterLaunchHandoff.begin(in: defaults, now: now)
        let later = ControlCenterLaunchHandoff.begin(in: defaults, now: now)
        ControlCenterLaunchHandoff.cancel(earlier, in: defaults)
        XCTAssertEqual(defaults.dictionary(forKey: ControlCenterLaunchHandoff.key)?["token"] as? String, later.uuidString)
        ControlCenterLaunchHandoff.cancel(later, in: defaults)
        XCTAssertFalse(ControlCenterLaunchHandoff.consume(in: defaults, now: now))
    }
}
