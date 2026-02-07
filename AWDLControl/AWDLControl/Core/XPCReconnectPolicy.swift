//
//  XPCReconnectPolicy.swift
//  AWDLControl
//
//  Backoff policy for reconnecting XPC channels.
//

import Foundation

enum XPCReconnectPolicy {
    static func delayForAttempt(_ attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return pow(2.0, Double(attempt - 1))
    }
}
