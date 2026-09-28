//
//  ChartDownsampling.swift
//  PingWarden
//
//  Pure helpers that bound how much the Dashboard chart draws and how often
//  it redraws. Generic over the sample type so the app's PingResult and the
//  tests' fixtures share one implementation.
//

import Foundation

enum ChartDownsampling {
    /// Upper bound on buckets per chart. Swift Charts slows sharply as marks
    /// grow, and 360 buckets is still finer than the chart's pixel width.
    static let maximumBuckets = 360

    /// Width of one time bucket for a timeframe: the timeframe divided into
    /// `maximumBuckets` equal slices.
    static func bucketSeconds(forTimeframeMinutes minutes: Int, maximumBuckets: Int = maximumBuckets) -> TimeInterval {
        guard minutes > 0, maximumBuckets > 0 else { return 0 }
        return TimeInterval(minutes * 60) / TimeInterval(maximumBuckets)
    }

    /// Whether the chart's data is due for a rebuild. A chart that only
    /// changes when a bucket fills does not need rebuilding for every
    /// sample, so it refreshes at about one bucket's width. The small slack
    /// keeps timer jitter from skipping every other refresh.
    static func isRefreshDue(now: Date, lastRefresh: Date?, bucketSeconds: TimeInterval) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= bucketSeconds * 0.9
    }

    /// Index of the first element newer than `cutoff`, by binary search.
    /// `items` must be sorted by ascending timestamp, which the rolling ping
    /// history is because probes are appended as they finish.
    static func firstIndex<T>(in items: [T], after cutoff: Date, timestamp: (T) -> Date) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if timestamp(items[middle]) > cutoff {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    /// Collapses samples into fixed buckets of absolute time,
    /// `floor(timestamp / bucketSeconds)`. Each bucket keeps its slowest
    /// successful sample, so a spike is never averaged away, plus its first
    /// failure, so an outage still breaks the line. Because bucket edges do
    /// not depend on the window's start, a new sample changes only the newest
    /// bucket and older points stay put instead of shimmering. Output keeps
    /// the input's order.
    static func bucketed<T>(
        _ items: ArraySlice<T>,
        bucketSeconds: TimeInterval,
        timestamp: (T) -> Date,
        latencyMs: (T) -> Double,
        success: (T) -> Bool
    ) -> [T] {
        guard bucketSeconds > 0 else { return Array(items) }
        var kept: [T] = []
        kept.reserveCapacity(min(items.count, maximumBuckets * 2))

        var currentBucket: Int64?
        var slowest: T?
        var firstFailure: T?

        func flush() {
            switch (slowest, firstFailure) {
            case let (success?, failure?):
                if timestamp(failure) < timestamp(success) {
                    kept.append(failure)
                    kept.append(success)
                } else {
                    kept.append(success)
                    kept.append(failure)
                }
            case let (success?, nil):
                kept.append(success)
            case let (nil, failure?):
                kept.append(failure)
            case (nil, nil):
                break
            }
            slowest = nil
            firstFailure = nil
        }

        for item in items {
            let bucket = Int64((timestamp(item).timeIntervalSince1970 / bucketSeconds).rounded(.down))
            if bucket != currentBucket {
                flush()
                currentBucket = bucket
            }
            if success(item) {
                if let current = slowest, latencyMs(current) >= latencyMs(item) {
                    continue
                }
                slowest = item
            } else if firstFailure == nil {
                firstFailure = item
            }
        }
        flush()
        return kept
    }

    /// Thins event markers so a burst draws one rule instead of dozens.
    /// An event is kept unless a kept event of the same kind lies less than
    /// `minimumSpacing` before it. Input must be sorted by timestamp.
    static func mergedEvents<T, Kind: Hashable>(
        _ events: [T],
        minimumSpacing: TimeInterval,
        timestamp: (T) -> Date,
        kind: (T) -> Kind
    ) -> [T] {
        guard minimumSpacing > 0 else { return events }
        var lastKept: [Kind: Date] = [:]
        var kept: [T] = []
        for event in events {
            let eventKind = kind(event)
            let time = timestamp(event)
            if let previous = lastKept[eventKind], time.timeIntervalSince(previous) < minimumSpacing {
                continue
            }
            lastKept[eventKind] = time
            kept.append(event)
        }
        return kept
    }
}
