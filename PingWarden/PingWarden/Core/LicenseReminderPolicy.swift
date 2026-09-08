import Foundation

/// Reminder timing never changes entitlement or the original transition deadline.
enum LicenseReminderPolicy {
    static let interval: TimeInterval = 7 * 24 * 3600

    static func isDue(
        now: Date,
        deadline: Date?,
        eligible: Bool,
        lastPresentedAt: Date?
    ) -> Bool {
        guard eligible, let deadline, now < deadline else { return false }
        let start = deadline.addingTimeInterval(-LicensePolicy.grandfatherInterval)
        // Older versions only stored whether the introductory notice was shown.
        // Use the original grant date as their baseline, never a new 90-day grant.
        let baseline = max(start, lastPresentedAt ?? start)
        return now.timeIntervalSince(baseline) >= interval
    }
}
