import Foundation
import XCTest
@testable import PingWardenCore

final class DiagnosticReportingTests: XCTestCase {
    func testReportKeepsAllowlistedDomainAndCodeOnly() {
        let error = NSError(
            domain: "SMAppServiceErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not reach probe.example.com at 192.0.2.4"]
        )
        let report = HelperProblemReport(problem: .registrationFailed, helperState: .notRegistered, error: error)
        XCTAssertEqual(report.errorDomain, "SMAppServiceErrorDomain")
        XCTAssertEqual(report.errorCode, 1)
        XCTAssertNil(report.failureReason)
        let tags = report.tags(appVersion: "4.3.3", macOSVersion: "15.5.0")
        XCTAssertEqual(tags, [
            "helper_problem": "registration_failed",
            "helper_state": "not_registered",
            "app_version": "4.3.3",
            "macos_version": "15.5.0",
            "error_domain": "SMAppServiceErrorDomain",
            "error_code": "1",
        ])
        let everything = (tags.values + report.fingerprint + [report.message]).joined(separator: " ")
        XCTAssertFalse(everything.contains("example"))
        XCTAssertFalse(everything.contains("192.0.2.4"))
    }

    func testUnlistedDomainIsReportedAsOther() {
        let report = HelperProblemReport(
            problem: .registrationFailed,
            helperState: .unknown,
            error: NSError(domain: "com.example.private-network", code: 7)
        )
        XCTAssertEqual(report.errorDomain, "other")
        XCTAssertEqual(report.errorCode, 7)
    }

    func testCommandFailuresMapToReasons() {
        XCTAssertEqual(HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .timedOut).failureReason, .timedOut)
        XCTAssertEqual(HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .noConnection).failureReason, .noConnection)
        XCTAssertEqual(HelperProblemReport(problem: .protectionDisableFailed, helperState: .enabled, failure: .declined).failureReason, .declined)
        let rejected = HelperProblemReport(problem: .repairFailed, helperState: .enabled, failure: .rejected(code: 4097))
        XCTAssertEqual(rejected.failureReason, .xpcError)
        XCTAssertEqual(rejected.errorDomain, NSCocoaErrorDomain)
        XCTAssertEqual(rejected.errorCode, 4097)
    }

    func testFingerprintIsStableAndIgnoresHelperState() {
        let first = HelperProblemReport(problem: .repairFailed, helperState: .enabled, failure: .timedOut)
        let second = HelperProblemReport(problem: .repairFailed, helperState: .notFound, failure: .timedOut)
        XCTAssertEqual(first.fingerprint, ["helper-problem", "repair_failed", "timed_out", "none", "none"])
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.message, "Helper problem: repair_failed")
    }

    func testRateLimiterAllowsOncePerIntervalAndCapsTheRun() {
        var limiter = DiagnosticEventRateLimiter(minimumInterval: 60, sessionCap: 3)
        XCTAssertTrue(limiter.shouldSend(key: "a", now: 0))
        XCTAssertFalse(limiter.shouldSend(key: "a", now: 59))
        XCTAssertTrue(limiter.shouldSend(key: "b", now: 59))
        XCTAssertTrue(limiter.shouldSend(key: "a", now: 60))
        XCTAssertEqual(limiter.sentCount, 3)
        XCTAssertFalse(limiter.shouldSend(key: "c", now: 10_000), "the per-run cap holds across keys and time")
    }

    func testDefaultRateLimit() {
        let limiter = DiagnosticEventRateLimiter()
        XCTAssertEqual(limiter.minimumInterval, 30 * 60)
        XCTAssertEqual(limiter.sessionCap, 10)
    }

    func testBreadcrumbsAreClosedValues() {
        XCTAssertEqual(StateBreadcrumb.setupStarted.category, "app.setup")
        XCTAssertEqual(StateBreadcrumb.repairFailed.category, "app.repair")
        XCTAssertEqual(StateBreadcrumb.protectionDisabled.category, "app.protection")
        XCTAssertEqual(StateBreadcrumb.helperConnectionLost.category, "app.helper")
        XCTAssertEqual(StateBreadcrumb.allowedCategories, ["app.setup", "app.repair", "app.protection", "app.helper"])
        XCTAssertTrue(StateBreadcrumb.isAllowed(category: "app.repair", message: "repair.started"))
        XCTAssertFalse(StateBreadcrumb.isAllowed(category: "app.repair", message: "setup.started"))
        XCTAssertFalse(StateBreadcrumb.isAllowed(category: "app.repair", message: "game.example.com"))
        XCTAssertFalse(StateBreadcrumb.isAllowed(category: "ui.click", message: nil))
    }

    func testReleaseMatchesReleaseScript() {
        XCTAssertEqual(DiagnosticRelease.releaseName(shortVersion: "4.3.3", build: "40303"), "com.amesvt.pingwarden@4.3.3+40303")
    }

    func testEnvironment() {
        XCTAssertEqual(DiagnosticRelease.environment(shortVersion: "4.3.3", betaChannelEnabled: false, isDebugBuild: false), "production")
        XCTAssertEqual(DiagnosticRelease.environment(shortVersion: "4.3.3", betaChannelEnabled: true, isDebugBuild: false), "beta")
        XCTAssertEqual(DiagnosticRelease.environment(shortVersion: "4.4.0-beta.1", betaChannelEnabled: false, isDebugBuild: false), "beta")
        XCTAssertEqual(DiagnosticRelease.environment(shortVersion: "4.4.0-rc.2", betaChannelEnabled: false, isDebugBuild: false), "beta")
        XCTAssertEqual(DiagnosticRelease.environment(shortVersion: "4.3.3", betaChannelEnabled: true, isDebugBuild: true), "development")
    }

    func testScrubberRedactsNetworkIdentifiers() {
        let scrubbed = DiagnosticScrubber.scrub(
            "connect to 192.0.2.10:443 and [2001:db8::1] and fe80::1%en0 via https://game.example.com/path?q=1, host speedtest.example.net, mail user@example.org"
        )
        for leaked in ["192.0.2.10", "2001:db8", "fe80", "https://", "game.example.com", "speedtest.example.net", "user@", "example.org"] {
            XCTAssertFalse(scrubbed.contains(leaked), "\(leaked) leaked in \(scrubbed)")
        }
        XCTAssertTrue(scrubbed.contains("<ip>"))
        XCTAssertTrue(scrubbed.contains("<host>"))
        XCTAssertTrue(scrubbed.contains("<url>"))
        XCTAssertTrue(scrubbed.contains("<email>"))
    }

    func testScrubberKeepsCodeIdentifiers() {
        let text = "*** -[__NSArrayM objectAtIndex:]: index 5 beyond bounds [0 .. 2] in PingWardenMonitor.swift:120 at 12:30:45 (NSRangeException)"
        XCTAssertEqual(DiagnosticScrubber.scrub(text), text)
    }

    func testScrubberRemovesHomeFolderAccountNames() {
        XCTAssertEqual(
            DiagnosticScrubber.scrubPath("/Users/jane.doe/Applications/Ping Warden.app/Contents/MacOS/Ping Warden"),
            "/Users/<user>/Applications/Ping Warden.app/Contents/MacOS/Ping Warden"
        )
        XCTAssertEqual(
            DiagnosticScrubber.scrubPath("/Applications/Ping Warden.app/Contents/MacOS/Ping Warden"),
            "/Applications/Ping Warden.app/Contents/MacOS/Ping Warden"
        )
        XCTAssertFalse(DiagnosticScrubber.scrub("failed at /Users/jane/Library/Logs/x.log").contains("jane"))
    }
}
