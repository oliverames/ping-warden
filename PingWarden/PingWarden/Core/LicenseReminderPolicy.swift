import Foundation

/// Reminder timing never changes entitlement or the original transition deadline.
enum LicenseReminderPolicy {
    /// Days remaining at which a reminder becomes due. Anchoring to the time
    /// left, rather than to a fixed cadence, keeps every reminder informative:
    /// each one tells the user something new about how close the deadline is.
    /// The introductory notice at first launch is presented separately.
    static let remainingDayThresholds: [Double] = [30, 7]

    /// The current notice consumes every threshold already reached.
    static func followUpMessage(daysRemaining: Int?) -> String {
        let activation = "Buying and activating your license stops these reminders."
        guard let daysRemaining, daysRemaining > 7 else {
            return "This is your final transition reminder."
        }
        if daysRemaining > 30 {
            return "We’ll remind you when 30 days and 7 days remain. " + activation
        }
        return "We’ll remind you again when 7 days remain. " + activation
    }

    static func isDue(
        now: Date,
        deadline: Date?,
        eligible: Bool,
        lastPresentedAt: Date?
    ) -> Bool {
        guard eligible, let deadline, now < deadline else { return false }
        let start = deadline.addingTimeInterval(-LicensePolicy.grandfatherInterval)
        // A clock rolled back before the grant must not fire a reminder.
        guard now >= start else { return false }
        // Older versions only stored whether the introductory notice was shown.
        // Use the original grant date as their baseline, never a new 90-day grant.
        let baseline = max(start, lastPresentedAt ?? start)
        // Due on the first crossing of a threshold. Thresholds already passed
        // before the baseline stay passed, so missed ones collapse into a
        // single reminder instead of stacking.
        return remainingDayThresholds.contains { threshold in
            let fireAt = deadline.addingTimeInterval(-threshold * 86400)
            return now >= fireAt && baseline < fireAt
        }
    }
}
