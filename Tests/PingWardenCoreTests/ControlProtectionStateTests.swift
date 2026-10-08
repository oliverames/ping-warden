import Foundation
import XCTest
@testable import PingWardenCore

final class ControlProtectionStateTests: XCTestCase {
    func testOnlyCompletePositiveEvidenceCanReportProtected() {
        for shared in [false, true] {
            for effective in [false, true] {
                for appRunning in [false, true] {
                    for interface in ControlProtectionState.InterfaceState.allCases {
                        let protected = ControlProtectionState.isProtected(
                            usesSharedPreferences: shared,
                            effectiveMonitoringEnabled: effective,
                            containingAppIsRunning: appRunning,
                            interfaceState: interface
                        )
                        if shared && effective && appRunning && interface == .down {
                            XCTAssertTrue(protected)
                        } else {
                            XCTAssertFalse(protected,
                                "Rejected evidence: shared=\(shared), effective=\(effective), app=\(appRunning), interface=\(interface)")
                        }
                    }
                }
            }
        }
    }

    func testAppCrashRejectsPersistedEffectiveStateDuringHelperGrace() {
        XCTAssertFalse(ControlProtectionState.isProtected(
            usesSharedPreferences: true,
            effectiveMonitoringEnabled: true,
            containingAppIsRunning: false,
            interfaceState: .down
        ))
    }

    func testRestoredInterfaceRejectsStaleEffectiveStateWhileAppIsRunning() {
        XCTAssertFalse(ControlProtectionState.isProtected(
            usesSharedPreferences: true,
            effectiveMonitoringEnabled: true,
            containingAppIsRunning: true,
            interfaceState: .up
        ))
    }

    func testExactContainingAppMatchesButAnotherInstallationDoesNot() {
        XCTAssertTrue(matchesApp(url: appURL))
        XCTAssertFalse(matchesApp(url: URL(fileURLWithPath: "/Applications/Other Copy/Ping Warden.app")))
        XCTAssertFalse(matchesApp(url: appURL, identifier: "com.example.other"))
        XCTAssertFalse(matchesApp(url: appURL, terminated: true))
    }

    func testUnavailableProcessIdentityCannotConfirmTheContainingApp() {
        XCTAssertFalse(matchesApp(url: nil))
        XCTAssertFalse(matchesApp(url: appURL, identifier: nil))
    }

    func testStandardizedContainingAppPathStillMatches() {
        XCTAssertTrue(matchesApp(url: URL(fileURLWithPath: "/Applications/./Ping Warden.app")))
    }

    private let appURL = URL(fileURLWithPath: "/Applications/Ping Warden.app")

    private func matchesApp(
        url: URL?,
        identifier: String? = "com.amesvt.pingwarden",
        terminated: Bool = false
    ) -> Bool {
        ControlProtectionState.matchesContainingApp(
            expectedBundleIdentifier: "com.amesvt.pingwarden",
            expectedBundleURL: appURL,
            runningBundleIdentifier: identifier,
            runningBundleURL: url,
            isTerminated: terminated
        )
    }
}
