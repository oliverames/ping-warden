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

    func testEnvironmentComesFromTheBuiltChannel() {
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: "production", isDebugBuild: false), "production")
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: "beta", isDebugBuild: false), "beta")
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: " Beta ", isDebugBuild: false), "beta")
        // Missing, unexpanded, or unknown values never claim beta.
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: nil, isDebugBuild: false), "production")
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: "$(PING_WARDEN_RELEASE_CHANNEL)", isDebugBuild: false), "production")
        XCTAssertEqual(DiagnosticRelease.environment(releaseChannel: "beta", isDebugBuild: true), "development")
        XCTAssertEqual(DiagnosticRelease.releaseChannelInfoKey, "PingWardenReleaseChannel")
    }

    func testRateLimitKeyIsTheProblemAlone() {
        let timeout = HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .timedOut)
        let declined = HelperProblemReport(problem: .protectionEnableFailed, helperState: .notFound, failure: .declined)
        let rejected = HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .rejected(code: 4099))
        XCTAssertEqual(timeout.rateLimitKey, "protection_enable_failed")
        XCTAssertEqual(Set([timeout.rateLimitKey, declined.rateLimitKey, rejected.rateLimitKey]).count, 1)
        XCTAssertNotEqual(timeout.fingerprint, declined.fingerprint, "fingerprints still separate reasons into issues")
        var limiter = DiagnosticEventRateLimiter(minimumInterval: 60, sessionCap: 10)
        XCTAssertTrue(limiter.shouldSend(key: timeout.rateLimitKey, now: 0))
        XCTAssertFalse(limiter.shouldSend(key: declined.rateLimitKey, now: 1))
        XCTAssertFalse(limiter.shouldSend(key: rejected.rateLimitKey, now: 2))
    }

    func testContextsKeepOnlyDisclosedKeys() {
        let filtered = DiagnosticContextPolicy.filter([
            "device": ["name": "Jane's Mac", "model": "Mac15,3", "family": "Mac", "arch": "arm64", "memory_size": 1, "boot_time": "x"],
            "os": ["name": "macOS", "version": "15.5", "build": "24F74", "kernel_version": "Darwin"],
            "app": ["app_version": "4.3.3", "app_build": "43300", "device_app_hash": "h", "app_start_time": "t", "app_identifier": "id"],
            "culture": ["locale": "en_US", "timezone": "America/New_York", "calendar": "gregorian"],
            "trace": ["trace_id": "t"],
        ])
        XCTAssertEqual(Set(filtered.keys), ["device", "os", "app"])
        XCTAssertEqual(Set(filtered["device"]!.keys), ["model", "family", "arch"])
        XCTAssertEqual(Set(filtered["os"]!.keys), ["name", "version", "build"])
        XCTAssertEqual(Set(filtered["app"]!.keys), ["app_version", "app_build"])
        XCTAssertTrue(DiagnosticContextPolicy.filter(["culture": ["locale": "en_US"], "device": ["name": "x"]]).isEmpty)
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

    func testScrubberRedactsHostsOnRealTLDsThatLookLikeFileTypes() {
        let scrubbed = DiagnosticScrubber.scrub("relay.zip and edge.mm and Monitor.swift")
        XCTAssertFalse(scrubbed.contains("relay.zip"), scrubbed)
        XCTAssertFalse(scrubbed.contains("edge.mm"), scrubbed)
        XCTAssertTrue(scrubbed.contains("Monitor.swift"), scrubbed)
        XCTAssertFalse(DiagnosticScrubber.codeSuffixes.contains("zip"))
        XCTAssertFalse(DiagnosticScrubber.codeSuffixes.contains("mm"))
    }

    private func assertRedacted(_ input: String, leaks: [String], marker: String, file: StaticString = #filePath, line: UInt = #line) {
        let scrubbed = DiagnosticScrubber.scrub(input, homeDirectory: "/Users/tester")
        for leak in leaks {
            XCTAssertFalse(scrubbed.contains(leak), "\(leak) leaked in \(scrubbed)", file: file, line: line)
        }
        XCTAssertTrue(scrubbed.contains(marker), "expected \(marker) in \(scrubbed)", file: file, line: line)
    }

    func testScrubberRedactsUnicodeAndPunycodeHosts() {
        assertRedacted("relay.xn--p1ai refused", leaks: ["relay", "xn--p1ai"], marker: "<host>")
        assertRedacted("relay.рф refused", leaks: ["relay", "рф"], marker: "<host>")
        assertRedacted("пример.испытание timed out", leaks: ["пример"], marker: "<host>")
        assertRedacted("xn--80ak6aa92e.com timed out", leaks: ["xn--80ak6aa92e"], marker: "<host>")
        assertRedacted("mail user@пример.рф", leaks: ["user", "пример"], marker: "<email>")
    }

    func testScrubberRedactsMixedIPv6AsOneToken() {
        for address in ["::ffff:192.0.2.1", "2001:db8:abcd::192.0.2.1", "64:ff9b::198.51.100.7"] {
            let scrubbed = DiagnosticScrubber.scrub("peer \(address) closed", homeDirectory: "/Users/tester")
            XCTAssertEqual(scrubbed, "peer <ip> closed", address)
        }
        XCTAssertEqual(DiagnosticScrubber.scrub("bind fe80::1%en0 failed"), "bind <ip> failed")
        XCTAssertEqual(DiagnosticScrubber.scrub("to [2001:db8::1]:443"), "to [<ip>]:443")
    }

    func testScrubberRedactsMACAddresses() {
        for mac in ["a4:83:e7:12:34:56", "A4-83-E7-12-34-56", "a483.e712.3456"] {
            XCTAssertEqual(DiagnosticScrubber.scrub("router \(mac) seen"), "router <mac> seen", mac)
        }
        // Mixed separators are not one address.
        XCTAssertEqual(DiagnosticScrubber.scrub("12:30:45"), "12:30:45")
    }

    func testScrubberRedactsSchemelessURLsWithPortAndPath() {
        XCTAssertEqual(
            DiagnosticScrubber.scrub("GET www.example.com:8443/v2/session?token=abc failed"),
            "GET <host> failed"
        )
        XCTAssertEqual(DiagnosticScrubber.scrub("probe game.example.net/ping"), "probe <host>")
        XCTAssertEqual(DiagnosticScrubber.scrub("see https://example.com/a?b=c."), "see <url>")
    }

    func testScrubberRedactsOtherHomePathForms() {
        XCTAssertEqual(DiagnosticScrubber.scrubPath(#"C:\Users\Jane Doe\AppData\x.log"#, homeDirectory: "/Users/tester"), #"C:\Users\<user>\AppData\x.log"#)
        XCTAssertEqual(DiagnosticScrubber.scrubPath("~jane/Library/x", homeDirectory: "/Users/tester"), "~<user>/Library/x")
        XCTAssertEqual(DiagnosticScrubber.scrubPath("~/Library/x", homeDirectory: "/Users/tester"), "~/Library/x")
        XCTAssertEqual(DiagnosticScrubber.scrubPath("/home/jane/.config/x", homeDirectory: "/Users/tester"), "/home/<user>/.config/x")
    }

    func testScrubberRedactsKnownIdentifiers() {
        let scrubbed = DiagnosticScrubber.scrub(
            "Jane Doe's MacBook Pro opened by janedoe",
            knownIdentifiers: ["Jane Doe's MacBook Pro", "janedoe", "Jane Doe", "ab", ""]
        )
        XCTAssertEqual(scrubbed, "<name> opened by <name>")
        XCTAssertEqual(DiagnosticScrubber.scrub("about tab", knownIdentifiers: ["ab"]), "about tab", "short identifiers are ignored")
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

    func testScrubberRemovesHomeFoldersOutsideUsers() {
        let home = "/Network/Servers/files.example/Homes/jdoe"
        XCTAssertEqual(
            DiagnosticScrubber.scrubPath("\(home)/Applications/Ping Warden.app/Contents/MacOS/Ping Warden", homeDirectory: home),
            "~/Applications/Ping Warden.app/Contents/MacOS/Ping Warden"
        )
        XCTAssertEqual(DiagnosticScrubber.scrubPath("/private/var/jdoe-home/x", homeDirectory: "/private/var/jdoe-home/"), "~/x")
        // A home that is only a prefix of another folder name is left alone.
        XCTAssertEqual(DiagnosticScrubber.scrubPath("/opt/jdoe2/x", homeDirectory: "/opt/jdoe"), "/opt/jdoe2/x")
        // A root or single-component home never redacts unrelated paths.
        XCTAssertEqual(DiagnosticScrubber.scrubPath("/Applications/x", homeDirectory: "/"), "/Applications/x")
        XCTAssertEqual(DiagnosticScrubber.scrubPath("/var/x", homeDirectory: "/var"), "/var/x")
        XCTAssertFalse(
            DiagnosticScrubber.scrub("open \(home)/Library/x.plist failed", homeDirectory: home).contains("jdoe")
        )
    }
}
