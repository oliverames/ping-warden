import Foundation

@main
enum CoreLogicSmoke {
    static func main() {
        let now = Date()

        let empty = PingStatistics.calculate(from: [])
        assertEqual(empty.currentPing, 0, "Empty stats should report zero current ping")
        assertEqual(empty.quality, .poor, "Empty stats should be poor quality")

        let healthySamples = [
            PingSample(latencyMs: 12, success: true, timestamp: now),
            PingSample(latencyMs: 14, success: true, timestamp: now.addingTimeInterval(1)),
            PingSample(latencyMs: 10, success: true, timestamp: now.addingTimeInterval(2))
        ]
        let healthy = PingStatistics.calculate(from: healthySamples)
        assertNearlyEqual(healthy.currentPing, 10, "Current ping should be last successful sample")
        assertNearlyEqual(healthy.averagePing, 12, "Average ping should be arithmetic mean")
        assertNearlyEqual(healthy.jitter, 3, "Jitter should be mean absolute delta")
        assertNearlyEqual(healthy.packetLoss, 0, "No failures means zero packet loss")
        assertEqual(healthy.quality, .excellent, "Low-latency healthy samples should be excellent")

        let lossySamples = [
            PingSample(latencyMs: 120, success: true, timestamp: now),
            PingSample(latencyMs: 1000, success: false, timestamp: now.addingTimeInterval(1)),
            PingSample(latencyMs: 130, success: true, timestamp: now.addingTimeInterval(2))
        ]
        let lossy = PingStatistics.calculate(from: lossySamples)
        assertNearlyEqual(lossy.packetLoss, 33.3333333333, tolerance: 0.0001, "Packet loss should reflect failed ratio")
        assertEqual(lossy.quality, .poor, "High latency or loss should be poor")

        assertNearlyEqual(XPCReconnectPolicy.delayForAttempt(1), 1.0, "First retry delay should be 1 second")
        assertNearlyEqual(XPCReconnectPolicy.delayForAttempt(2), 2.0, "Second retry delay should be 2 seconds")
        assertNearlyEqual(XPCReconnectPolicy.delayForAttempt(3), 4.0, "Third retry delay should be 4 seconds")
        assertNearlyEqual(XPCReconnectPolicy.delayForAttempt(0), 0.0, "Non-positive attempts should return zero")

        print("core_logic_smoke.swift: all assertions passed")
    }

    @inline(__always)
    private static func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
        guard lhs == rhs else {
            fputs("Assertion failed: \(message)\nExpected: \(rhs)\nActual: \(lhs)\n", stderr)
            exit(1)
        }
    }

    @inline(__always)
    private static func assertNearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001, _ message: String) {
        guard abs(lhs - rhs) <= tolerance else {
            fputs("Assertion failed: \(message)\nExpected: \(rhs)\nActual: \(lhs)\n", stderr)
            exit(1)
        }
    }
}
