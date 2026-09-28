//
//  ChartTimeAxis.swift
//  PingWarden
//
//  X-axis ticks for the Dashboard's ping chart, aligned to the wall clock.
//

import Foundation

enum ChartTimeAxis {
    /// Spacing between ticks for a chart timeframe, chosen so each timeframe
    /// shows three to six labels on round clock values.
    static func tickStep(forTimeframeMinutes minutes: Int) -> TimeInterval {
        switch minutes {
        case ...1: return 15
        case ...5: return 60
        case ...30: return 5 * 60
        default: return 10 * 60
        }
    }

    /// Whether tick labels need seconds. Only the 1-minute view has ticks
    /// closer together than a minute.
    static func labelsIncludeSeconds(forTimeframeMinutes minutes: Int) -> Bool {
        tickStep(forTimeframeMinutes: minutes) < 60
    }

    /// Ticks on multiples of `step` since the epoch that fall inside the
    /// window. Deriving them from the window edges instead made every tick a
    /// new Date on every render, and Swift Charts kept a fresh set of axis
    /// label views for each one, so memory grew for as long as the Dashboard
    /// stayed open. Clock-aligned ticks stay identical until the window
    /// slides past the next boundary.
    static func tickDates(windowStart: Date, windowEnd: Date, step: TimeInterval) -> [Date] {
        guard step > 0, windowEnd > windowStart else { return [] }
        let first = (windowStart.timeIntervalSince1970 / step).rounded(.up) * step
        let last = windowEnd.timeIntervalSince1970
        return stride(from: first, through: last, by: step).map(Date.init(timeIntervalSince1970:))
    }

    static func tickDates(windowStart: Date, windowEnd: Date, timeframeMinutes: Int) -> [Date] {
        tickDates(
            windowStart: windowStart,
            windowEnd: windowEnd,
            step: tickStep(forTimeframeMinutes: timeframeMinutes)
        )
    }
}
