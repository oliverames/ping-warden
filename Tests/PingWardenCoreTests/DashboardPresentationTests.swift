//
//  DashboardPresentationTests.swift
//  PingWardenCoreTests
//
//  The Dashboard's pure presentation rules: clock-aligned axis ticks,
//  bucketed chart data, the hidden-window redraw gate, recap grading, the
//  probe's poll slices, and undoing a custom target removal.
//

import Foundation
import XCTest
@testable import PingWardenCore

private struct Sample: Equatable {
    let timestamp: Date
    let latencyMs: Double
    let success: Bool
}

private func bucketed(_ samples: [Sample], bucketSeconds: TimeInterval) -> [Sample] {
    ChartDownsampling.bucketed(
        samples[...],
        bucketSeconds: bucketSeconds,
        timestamp: \.timestamp,
        latencyMs: \.latencyMs,
        success: \.success
    )
}

final class ChartTimeAxisTests: XCTestCase {
    // A fixed instant that is not on any tick boundary.
    private let reference = Date(timeIntervalSince1970: 1_790_000_007.25)

    func testTicksAreIdenticalAcrossRendersOneSecondApart() {
        for minutes in [1, 5, 15, 30, 60] {
            let end = reference
            let later = end.addingTimeInterval(1)
            let span = TimeInterval(minutes * 60)
            let first = ChartTimeAxis.tickDates(windowStart: end - span, windowEnd: end, timeframeMinutes: minutes)
            let second = ChartTimeAxis.tickDates(windowStart: later - span, windowEnd: later, timeframeMinutes: minutes)
            XCTAssertFalse(first.isEmpty, "\(minutes) min has ticks")
            XCTAssertEqual(first, second, "\(minutes) min ticks stay the same Date values when the window slides one second")
        }
    }

    func testTicksFallOnClockBoundariesInsideTheWindow() {
        for minutes in [1, 5, 15, 30, 60] {
            let step = ChartTimeAxis.tickStep(forTimeframeMinutes: minutes)
            let start = reference - TimeInterval(minutes * 60)
            let ticks = ChartTimeAxis.tickDates(windowStart: start, windowEnd: reference, timeframeMinutes: minutes)
            for tick in ticks {
                XCTAssertEqual(tick.timeIntervalSince1970.truncatingRemainder(dividingBy: step), 0, accuracy: 1e-6)
                XCTAssertGreaterThanOrEqual(tick, start)
                XCTAssertLessThanOrEqual(tick, reference)
            }
            XCTAssertTrue((3...6).contains(ticks.count), "\(minutes) min shows \(ticks.count) ticks")
        }
    }

    func testStepsAndLabelsPerTimeframe() {
        XCTAssertEqual(ChartTimeAxis.tickStep(forTimeframeMinutes: 1), 15)
        XCTAssertEqual(ChartTimeAxis.tickStep(forTimeframeMinutes: 5), 60)
        XCTAssertEqual(ChartTimeAxis.tickStep(forTimeframeMinutes: 15), 300)
        XCTAssertEqual(ChartTimeAxis.tickStep(forTimeframeMinutes: 30), 300)
        XCTAssertEqual(ChartTimeAxis.tickStep(forTimeframeMinutes: 60), 600)
        XCTAssertTrue(ChartTimeAxis.labelsIncludeSeconds(forTimeframeMinutes: 1))
        for minutes in [5, 15, 30, 60] {
            XCTAssertFalse(ChartTimeAxis.labelsIncludeSeconds(forTimeframeMinutes: minutes))
        }
    }

    func testEmptyOrInvertedWindowHasNoTicks() {
        XCTAssertTrue(ChartTimeAxis.tickDates(windowStart: reference, windowEnd: reference, step: 15).isEmpty)
        XCTAssertTrue(ChartTimeAxis.tickDates(windowStart: reference, windowEnd: reference - 60, step: 15).isEmpty)
    }
}

final class ChartDownsamplingTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_790_000_000)

    private func steadySamples(count: Int, from start: Date, interval: TimeInterval = 1) -> [Sample] {
        (0..<count).map { index in
            Sample(
                timestamp: start.addingTimeInterval(Double(index) * interval),
                latencyMs: Double(10 + (index * 7) % 23),
                success: true
            )
        }
    }

    func testOlderPointsStayPutWhenTheWindowSlides() {
        let bucket = ChartDownsampling.bucketSeconds(forTimeframeMinutes: 60)
        let samples = steadySamples(count: 3_601, from: origin)
        // One more sample arrives and the oldest leaves the window.
        let slid = Array(samples.dropFirst()) + steadySamples(count: 1, from: origin.addingTimeInterval(3_601))
        let before = bucketed(samples, bucketSeconds: bucket)
        let after = bucketed(slid, bucketSeconds: bucket)
        // Every bucket except the two edges must be identical.
        let interiorBefore = Array(before.dropFirst().dropLast())
        let interiorAfter = Array(after.dropFirst().dropLast())
        XCTAssertEqual(interiorBefore.count, interiorAfter.count)
        XCTAssertEqual(interiorBefore, interiorAfter, "interior chart points do not shimmer")
    }

    func testBucketKeepsTheSlowestSuccessAndTheFirstFailure() {
        let samples = [
            Sample(timestamp: origin, latencyMs: 12, success: true),
            Sample(timestamp: origin + 1, latencyMs: 216, success: true),
            Sample(timestamp: origin + 2, latencyMs: 1_000, success: false),
            Sample(timestamp: origin + 3, latencyMs: 1_000, success: false),
            Sample(timestamp: origin + 4, latencyMs: 30, success: true),
        ]
        let kept = bucketed(samples, bucketSeconds: 10)
        XCTAssertEqual(kept, [samples[1], samples[2]], "the spike survives and the outage still breaks the line")
    }

    func testAnHourOfOneSecondSamplesIsBounded() {
        let samples = steadySamples(count: 3_900, from: origin)
        let window = Array(samples.suffix(3_600))
        let kept = bucketed(window, bucketSeconds: ChartDownsampling.bucketSeconds(forTimeframeMinutes: 60))
        XCTAssertLessThanOrEqual(kept.count, ChartDownsampling.maximumBuckets + 1)
        XCTAssertGreaterThanOrEqual(kept.count, ChartDownsampling.maximumBuckets - 1)
    }

    func testShortTimeframesKeepEverySample() {
        let samples = steadySamples(count: 60, from: origin)
        let bucket = ChartDownsampling.bucketSeconds(forTimeframeMinutes: 1)
        XCTAssertEqual(bucketed(samples, bucketSeconds: bucket), samples)
    }

    func testFirstIndexMatchesALinearFilter() {
        let samples = steadySamples(count: 500, from: origin)
        for offset in [-5.0, 0, 0.5, 1, 250.25, 499, 500, 900] {
            let cutoff = origin.addingTimeInterval(offset)
            let expected = samples.firstIndex { $0.timestamp > cutoff } ?? samples.count
            XCTAssertEqual(ChartDownsampling.firstIndex(in: samples, after: cutoff, timestamp: \.timestamp), expected)
        }
        XCTAssertEqual(ChartDownsampling.firstIndex(in: [Sample](), after: origin, timestamp: \.timestamp), 0)
    }

    func testEventBurstsMergeByKind() {
        struct Event { let timestamp: Date; let kind: Int }
        var events = (0..<100).map { Event(timestamp: origin + Double($0), kind: 0) }
        events += (0..<100).map { Event(timestamp: origin + Double($0) + 0.5, kind: 1) }
        events.sort { $0.timestamp < $1.timestamp }
        let merged = ChartDownsampling.mergedEvents(events, minimumSpacing: 40, timestamp: \.timestamp, kind: \.kind)
        XCTAssertEqual(merged.filter { $0.kind == 0 }.map(\.timestamp), [origin, origin + 40, origin + 80])
        XCTAssertEqual(merged.filter { $0.kind == 1 }.count, 3, "each kind thins on its own")
    }

    func testRefreshCadenceFollowsTheBucketWidth() {
        let now = origin
        XCTAssertTrue(ChartDownsampling.isRefreshDue(now: now, lastRefresh: nil, bucketSeconds: 10))
        XCTAssertFalse(ChartDownsampling.isRefreshDue(now: now, lastRefresh: now - 2, bucketSeconds: 10))
        XCTAssertTrue(ChartDownsampling.isRefreshDue(now: now, lastRefresh: now - 9.5, bucketSeconds: 10))
        // One-minute buckets are narrower than any sample interval, so every
        // sample refreshes.
        let oneMinute = ChartDownsampling.bucketSeconds(forTimeframeMinutes: 1)
        XCTAssertTrue(ChartDownsampling.isRefreshDue(now: now, lastRefresh: now - 1, bucketSeconds: oneMinute))
    }
}

final class DeferredRefreshGateTests: XCTestCase {
    func testVisibilityCombinesOcclusionMiniaturizeAndHide() {
        XCTAssertTrue(PresentationVisibility.isVisible(windowOnScreen: true, isMiniaturized: false, appIsHidden: false))
        XCTAssertFalse(PresentationVisibility.isVisible(windowOnScreen: false, isMiniaturized: false, appIsHidden: false))
        XCTAssertFalse(PresentationVisibility.isVisible(windowOnScreen: true, isMiniaturized: true, appIsHidden: false))
        XCTAssertFalse(PresentationVisibility.isVisible(windowOnScreen: true, isMiniaturized: false, appIsHidden: true))
    }

    func testChangesWhileHiddenAreDeferredAndDrawnOnceOnReturn() {
        var gate = DeferredRefreshGate()
        XCTAssertTrue(gate.noteChange(), "a visible view draws each change")
        XCTAssertFalse(gate.setVisible(false))
        for _ in 0..<30 {
            XCTAssertFalse(gate.noteChange(), "a hidden view skips the redraw")
        }
        XCTAssertTrue(gate.setVisible(true), "becoming visible asks for one catch-up redraw")
        XCTAssertFalse(gate.setVisible(true), "a repeated visible report does not redraw again")
        XCTAssertTrue(gate.noteChange())
    }

    func testReturningWithoutChangesNeedsNoRedraw() {
        var gate = DeferredRefreshGate()
        XCTAssertFalse(gate.setVisible(false))
        XCTAssertFalse(gate.setVisible(true))
    }

    func testResetStartsVisible() {
        var gate = DeferredRefreshGate()
        _ = gate.setVisible(false)
        _ = gate.noteChange()
        gate.reset()
        XCTAssertEqual(gate, DeferredRefreshGate())
        XCTAssertTrue(gate.noteChange())
    }
}

final class SessionRecapOutcomeTests: XCTestCase {
    func testOutcomeReflectsTheWorseOfLatencyAndLoss() {
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 0, medianLatencyMs: 0, packetLossPercent: 100), .noMeasurements)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 18, packetLossPercent: 0), .good)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 49.9, packetLossPercent: 0.5), .good)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 72, packetLossPercent: 0), .fair)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 18, packetLossPercent: 2), .fair)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 216, packetLossPercent: 0), .poor)
        XCTAssertEqual(SessionRecapOutcome.evaluate(successfulSampleCount: 90, medianLatencyMs: 18, packetLossPercent: 7), .poor)
    }
}

final class TCPProbePollSliceTests: XCTestCase {
    func testUncancellableProbesWaitForTheWholeRemainder() {
        XCTAssertEqual(TCPProbe.pollSliceMilliseconds(remaining: 1_000, isCancellable: false), 1_000)
        XCTAssertEqual(TCPProbe.pollSliceMilliseconds(remaining: 40, isCancellable: false), 40)
    }

    func testCancellableProbesStillCheckEveryHundredMilliseconds() {
        XCTAssertEqual(TCPProbe.pollSliceMilliseconds(remaining: 1_000, isCancellable: true), 100)
        XCTAssertEqual(TCPProbe.pollSliceMilliseconds(remaining: 40, isCancellable: true), 40)
    }
}

final class CustomPingTargetUndoTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = TestDefaultsSuite.name("PingWardenCoreTests.undo")
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testInsertRestoresARemovedTargetInPlace() {
        let store = CustomPingTargetStore(userDefaults: defaults)
        let first = CustomPingTarget(displayName: "First", host: "one.example", port: 53)
        let second = CustomPingTarget(displayName: "Second", host: "two.example", port: 53)
        let third = CustomPingTarget(displayName: "Third", host: "three.example", port: 53)
        [first, second, third].forEach { store.add($0) }

        store.remove(id: second.id)
        XCTAssertEqual(store.insert(second, at: 1), [first, second, third])
        XCTAssertEqual(store.load(), [first, second, third], "the restored order is persisted")
        XCTAssertEqual(store.insert(second, at: 0), [first, second, third], "restoring twice never duplicates")
    }

    func testInsertClampsAStaleIndex() {
        let store = CustomPingTargetStore(userDefaults: defaults)
        let only = CustomPingTarget(displayName: "Only", host: "only.example", port: 53)
        XCTAssertEqual(store.insert(only, at: 9), [only])
    }

    func testHostErrorPointsToThePortFieldWithoutADirection() {
        let message = CustomPingTargetValidationError.hostInvalid.userMessage
        XCTAssertFalse(message.contains("below"), "the Port field sits above the message")
        XCTAssertTrue(message.contains("Port field"))
    }
}
