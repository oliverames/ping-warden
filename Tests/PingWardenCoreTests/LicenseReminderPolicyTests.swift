import XCTest
@testable import PingWardenCore

final class LicenseReminderPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private var deadline: Date { start.addingTimeInterval(LicensePolicy.grandfatherInterval) }

    private func due(day: Double, eligible: Bool = true, lastDay: Double? = nil) -> Bool {
        LicenseReminderPolicy.isDue(now: start.addingTimeInterval(day * 86400), deadline: deadline,
            eligible: eligible, lastPresentedAt: lastDay.map { start.addingTimeInterval($0 * 86400) })
    }

    func testFirstWeekBoundary() {
        XCTAssertFalse(due(day: 7 - 1.0 / 86400))
        XCTAssertTrue(due(day: 7))
    }

    func testRelaunchUsesPersistedPresentationDate() {
        // Simulate reloading the stored timestamp after a launch at day 10.
        let storedTimestamp = start.addingTimeInterval(10 * 86400).timeIntervalSince1970
        let reloaded = Date(timeIntervalSince1970: storedTimestamp)
        XCTAssertFalse(LicenseReminderPolicy.isDue(now: start.addingTimeInterval(16 * 86400),
            deadline: deadline, eligible: true, lastPresentedAt: reloaded))
        XCTAssertTrue(due(day: 17, lastDay: 10))
    }

    func testMissedWeeksProduceOneReminderThenWaitAFullWeek() {
        XCTAssertTrue(due(day: 40, lastDay: 7))
        XCTAssertFalse(due(day: 40, lastDay: 40))
        XCTAssertFalse(due(day: 46, lastDay: 40))
        XCTAssertTrue(due(day: 47, lastDay: 40))
    }

    func testLegacyInstallsUseOriginalTransitionStart() {
        XCTAssertTrue(due(day: 30))
        XCTAssertFalse(due(day: 3))
    }

    func testPaidOrOtherwiseIneligibleInstallsAreSuppressed() {
        XCTAssertFalse(due(day: 30, eligible: false))
    }

    func testNoReminderAtOrAfterExpiry() {
        XCTAssertTrue(due(day: 89))
        XCTAssertFalse(due(day: 90))
        XCTAssertFalse(due(day: 100))
    }

    func testNoTransitionAndClockRollbackAreSuppressed() {
        XCTAssertFalse(LicenseReminderPolicy.isDue(now: start, deadline: nil, eligible: true, lastPresentedAt: nil))
        XCTAssertFalse(due(day: -1))
        XCTAssertFalse(due(day: 20, lastDay: 21))
    }

    func testTimestampBeforeGrantCannotAccelerateFirstReminder() {
        XCTAssertFalse(due(day: 1, lastDay: -20))
    }
}
