//
//  SessionRecapOutcome.swift
//  PingWarden
//
//  One overall grade for a latency session recap, so its header can say at a
//  glance whether the session went well.
//

import Foundation

enum SessionRecapOutcome: Equatable {
    case noMeasurements
    case good
    case fair
    case poor

    /// Grades a session by its median latency and probe failures, using the
    /// same bands as the Dashboard's colors: under 50 ms is good, under
    /// 100 ms is fair. Cloud gaming tolerates almost no loss, so 1% of
    /// probes failing already makes a session fair and 5% makes it poor.
    /// The worse of the two measures wins.
    static func evaluate(
        successfulSampleCount: Int,
        medianLatencyMs: Double,
        packetLossPercent: Double
    ) -> SessionRecapOutcome {
        guard successfulSampleCount > 0 else { return .noMeasurements }

        let latency: SessionRecapOutcome
        if medianLatencyMs < 50 {
            latency = .good
        } else if medianLatencyMs < 100 {
            latency = .fair
        } else {
            latency = .poor
        }

        let loss: SessionRecapOutcome
        if packetLossPercent < 1 {
            loss = .good
        } else if packetLossPercent < 5 {
            loss = .fair
        } else {
            loss = .poor
        }

        return latency.severity >= loss.severity ? latency : loss
    }

    private var severity: Int {
        switch self {
        case .noMeasurements: return 0
        case .good: return 1
        case .fair: return 2
        case .poor: return 3
        }
    }
}
