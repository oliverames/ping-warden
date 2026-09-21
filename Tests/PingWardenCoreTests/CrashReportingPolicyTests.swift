import Foundation
import XCTest
@testable import PingWardenCore

final class CrashReportingPolicyTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "PingWardenCrashReportingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testMissingChoiceEnablesReportingWithoutPersistingConsent() {
        CrashReportingPolicy.registerDefault(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: CrashReportingPolicy.preferenceKey))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[CrashReportingPolicy.preferenceKey])
    }

    func testSavedChoicesSurviveDefaultRegistrationAndRelaunch() {
        for enabled in [false, true] {
            defaults.set(enabled, forKey: CrashReportingPolicy.preferenceKey)
            CrashReportingPolicy.registerDefault(in: defaults)
            XCTAssertEqual(defaults.bool(forKey: CrashReportingPolicy.preferenceKey), enabled)
            let relaunched = UserDefaults(suiteName: suite)!
            CrashReportingPolicy.registerDefault(in: relaunched)
            XCTAssertEqual(relaunched.bool(forKey: CrashReportingPolicy.preferenceKey), enabled)
        }
    }

    func testOptOutTakesEffectImmediatelyAndPersists() {
        CrashReportingPolicy.registerDefault(in: defaults)
        defaults.set(false, forKey: CrashReportingPolicy.preferenceKey)
        XCTAssertFalse(defaults.bool(forKey: CrashReportingPolicy.preferenceKey))
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?[CrashReportingPolicy.preferenceKey] as? Bool, false)
    }

    func testRemovalDoesNotReenableReportingWhenPreferencesAreCleared() {
        CrashReportingPolicy.registerDefault(in: defaults)
        defaults.set(true, forKey: CrashReportingPolicy.preferenceKey)
        CrashReportingPolicy.prepareForRemoval(in: defaults)
        defaults.removePersistentDomain(forName: suite)
        XCTAssertFalse(defaults.bool(forKey: CrashReportingPolicy.preferenceKey))
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[CrashReportingPolicy.preferenceKey])
    }
}
