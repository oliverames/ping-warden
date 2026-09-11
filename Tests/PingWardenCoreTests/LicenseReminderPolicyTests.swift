import XCTest
@testable import PingWardenCore

final class LicenseReminderPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private var deadline: Date { start.addingTimeInterval(LicensePolicy.grandfatherInterval) }

    /// Day 60 leaves 30 days; day 83 leaves 7. Those are the two thresholds.
    private func due(day: Double, eligible: Bool = true, lastDay: Double? = nil) -> Bool {
        LicenseReminderPolicy.isDue(now: start.addingTimeInterval(day * 86400), deadline: deadline,
            eligible: eligible, lastPresentedAt: lastDay.map { start.addingTimeInterval($0 * 86400) })
    }

    func testQuietUntilThirtyDaysRemain() {
        XCTAssertFalse(due(day: 0))
        XCTAssertFalse(due(day: 7))
        XCTAssertFalse(due(day: 30))
        XCTAssertFalse(due(day: 60 - 1.0 / 86400))
    }

    func testDueWhenThirtyDaysRemain() {
        XCTAssertTrue(due(day: 60))
    }

    func testNotDueAgainUntilSevenDaysRemain() {
        XCTAssertFalse(due(day: 61, lastDay: 60))
        XCTAssertFalse(due(day: 82, lastDay: 60))
        XCTAssertTrue(due(day: 83, lastDay: 60))
    }

    func testFinalReminderDoesNotRepeat() {
        XCTAssertFalse(due(day: 84, lastDay: 83))
        XCTAssertFalse(due(day: 89, lastDay: 83))
    }

    func testMissedThresholdsCollapseIntoOneReminder() {
        // Never presented, first launch late in the window: one reminder, not two.
        XCTAssertTrue(due(day: 85))
        XCTAssertFalse(due(day: 86, lastDay: 85))
    }

    func testRelaunchUsesPersistedPresentationDate() {
        let storedTimestamp = start.addingTimeInterval(60 * 86400).timeIntervalSince1970
        let reloaded = Date(timeIntervalSince1970: storedTimestamp)
        XCTAssertFalse(LicenseReminderPolicy.isDue(now: start.addingTimeInterval(70 * 86400),
            deadline: deadline, eligible: true, lastPresentedAt: reloaded))
    }

    func testLegacyInstallsUseOriginalTransitionStart() {
        // No stored timestamp still anchors to the grant, never to a fresh window.
        XCTAssertFalse(due(day: 3))
        XCTAssertTrue(due(day: 60))
    }

    func testPaidOrOtherwiseIneligibleInstallsAreSuppressed() {
        XCTAssertFalse(due(day: 60, eligible: false))
        XCTAssertFalse(due(day: 83, eligible: false))
    }

    func testNoReminderAtOrAfterExpiry() {
        XCTAssertTrue(due(day: 89))
        XCTAssertFalse(due(day: 90))
        XCTAssertFalse(due(day: 100))
    }

    func testNoTransitionAndClockRollbackAreSuppressed() {
        XCTAssertFalse(LicenseReminderPolicy.isDue(now: start, deadline: nil, eligible: true, lastPresentedAt: nil))
        XCTAssertFalse(due(day: -1))
        XCTAssertFalse(due(day: 70, lastDay: 71))
    }

    func testTimestampBeforeGrantCannotAccelerateFirstReminder() {
        XCTAssertFalse(due(day: 1, lastDay: -20))
    }
}
