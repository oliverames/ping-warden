import Foundation
import XCTest
@testable import PingWardenCore

final class ControlCenterRefreshPolicyTests: XCTestCase {
    func testFirstRequestOpensOneWindow() {
        var coalescer = ControlCenterRefreshCoalescer(window: 0.5)
        XCTAssertEqual(coalescer.request(.appLaunch, controlCenterAvailable: true), 0.5)
        XCTAssertTrue(coalescer.hasPendingReload)
    }

    func testRequestsInsideTheWindowCoalesce() {
        var coalescer = ControlCenterRefreshCoalescer(window: 0.5)
        XCTAssertNotNil(coalescer.request(.appLaunch, controlCenterAvailable: true))
        XCTAssertNil(coalescer.request(.helperRecovered, controlCenterAvailable: true))
        XCTAssertNil(coalescer.request(.appLaunch, controlCenterAvailable: true))
        XCTAssertNil(coalescer.request(.repairFinished, controlCenterAvailable: true))
        XCTAssertEqual(coalescer.flush(), [.appLaunch, .helperRecovered, .repairFinished])
    }

    func testFlushClosesTheWindowSoTheNextRequestReloadsAgain() {
        var coalescer = ControlCenterRefreshCoalescer()
        XCTAssertNotNil(coalescer.request(.systemWake, controlCenterAvailable: true))
        XCTAssertEqual(coalescer.flush(), [.systemWake])
        XCTAssertFalse(coalescer.hasPendingReload)
        XCTAssertEqual(coalescer.flush(), [], "A second flush has nothing to reload")
        XCTAssertEqual(coalescer.request(.helperRecovered, controlCenterAvailable: true),
                       ControlCenterRefreshCoalescer.defaultWindow)
    }

    func testUnavailableControlCenterNeverSchedulesAReload() {
        var coalescer = ControlCenterRefreshCoalescer()
        for trigger in ControlCenterRefreshTrigger.allCases {
            XCTAssertNil(coalescer.request(trigger, controlCenterAvailable: false))
        }
        XCTAssertFalse(coalescer.hasPendingReload)
        XCTAssertEqual(coalescer.flush(), [])
    }

    func testNegativeWindowIsClampedToImmediate() {
        var coalescer = ControlCenterRefreshCoalescer(window: -1)
        XCTAssertEqual(coalescer.request(.appLaunch, controlCenterAvailable: true), 0)
    }

    func testDefaultWindowIsShortEnoughForLaunch() {
        XCTAssertGreaterThan(ControlCenterRefreshCoalescer.defaultWindow, 0)
        XCTAssertLessThanOrEqual(ControlCenterRefreshCoalescer.defaultWindow, 1)
    }
}
