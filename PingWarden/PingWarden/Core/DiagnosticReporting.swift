// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import Foundation

// Foundation-only rules for what Ping Warden's crash and error reporting may
// send. Everything here produces closed sets of values (enum raw values,
// allowlisted error domains, numeric codes) so an event can never carry a
// ping target, host name, IP address, network name, or license key. The
// Sentry-facing code in CrashReporter.swift only forwards what these types
// produce.

/// The helper's registration status, reduced to a fixed vocabulary.
enum HelperDiagnosticState: String, Sendable, CaseIterable {
    case enabled
    case notRegistered = "not_registered"
    case requiresApproval = "requires_approval"
    case notFound = "not_found"
    case unknown
}

/// A helper problem worth one non-fatal error event. Raw values are stable:
/// they are part of each event's fingerprint, so renaming one splits an
/// existing Sentry issue.
enum HelperProblem: String, Sendable, CaseIterable {
    /// The app bundle is missing the helper binary or its launchd plist.
    case helperBundleInvalid = "helper_bundle_invalid"
    /// `SMAppService.register()` threw an error that is not a pending approval.
    case registrationFailed = "registration_failed"
    /// Registration polled back to Not Registered and never completed.
    case registrationIncomplete = "registration_incomplete"
    /// Approval in Login Items did not arrive before the poll's deadline.
    case registrationApprovalTimedOut = "registration_approval_timed_out"
    /// Repair finished without a helper that answers.
    case repairFailed = "repair_failed"
    /// The helper did not confirm, or declined, turning protection on.
    case protectionEnableFailed = "protection_enable_failed"
    /// The helper did not confirm, or declined, turning protection off.
    case protectionDisableFailed = "protection_disable_failed"
    /// The helper refused to restore protection after a reconnect.
    case protectionReassertFailed = "protection_reassert_failed"
    /// Reconnect attempts ran out while protection was requested.
    case helperConnectionLost = "helper_connection_lost"
    /// The helper did not answer a health check (Run Test).
    case helperUnresponsive = "helper_unresponsive"
}

/// Why a helper request failed, as a fixed vocabulary.
enum HelperFailureReason: String, Sendable {
    case timedOut = "timed_out"
    case noConnection = "no_connection"
    case xpcError = "xpc_error"
    case declined

    init(_ failure: HelperCommandFailure) {
        switch failure {
        case .timedOut: self = .timedOut
        case .noConnection: self = .noConnection
        case .rejected: self = .xpcError
        case .declined: self = .declined
        }
    }
}

/// One scrubbed helper problem: every field is an enum value, an allowlisted
/// error domain, or a number.
struct HelperProblemReport: Equatable, Sendable {
    /// Error domains whose names are reported as-is. Any other domain is
    /// reported as `other`, so a framework that put context in its domain
    /// string could not leak it.
    static let reportableErrorDomains: Set<String> = [
        "SMAppServiceErrorDomain",
        NSPOSIXErrorDomain,
        NSCocoaErrorDomain,
        NSOSStatusErrorDomain,
        NSMachErrorDomain,
    ]

    let problem: HelperProblem
    let helperState: HelperDiagnosticState
    let failureReason: HelperFailureReason?
    let errorDomain: String?
    let errorCode: Int?

    init(
        problem: HelperProblem,
        helperState: HelperDiagnosticState,
        failure: HelperCommandFailure? = nil,
        error: NSError? = nil
    ) {
        self.problem = problem
        self.helperState = helperState
        self.failureReason = failure.map(HelperFailureReason.init)
        if let error {
            errorDomain = Self.reportableDomain(error.domain)
            errorCode = error.code
        } else if case .rejected(let code)? = failure {
            // NSXPCConnection errors are Cocoa errors (4097, 4099, ...).
            errorDomain = NSCocoaErrorDomain
            errorCode = code
        } else {
            errorDomain = nil
            errorCode = nil
        }
    }

    static func reportableDomain(_ domain: String) -> String {
        reportableErrorDomains.contains(domain) ? domain : "other"
    }

    /// Groups events by what went wrong, not by when or on which Mac.
    var fingerprint: [String] {
        [
            "helper-problem",
            problem.rawValue,
            failureReason?.rawValue ?? "none",
            errorDomain ?? "none",
            errorCode.map(String.init) ?? "none",
        ]
    }

    /// A fixed message: the problem name and nothing else.
    var message: String {
        "Helper problem: \(problem.rawValue)"
    }

    /// Searchable tags. App and macOS versions come from the bundle and the
    /// system, never from user input.
    func tags(appVersion: String, macOSVersion: String) -> [String: String] {
        var tags = [
            "helper_problem": problem.rawValue,
            "helper_state": helperState.rawValue,
            "app_version": appVersion,
            "macos_version": macOSVersion,
        ]
        if let failureReason { tags["failure_reason"] = failureReason.rawValue }
        if let errorDomain { tags["error_domain"] = errorDomain }
        if let errorCode { tags["error_code"] = String(errorCode) }
        return tags
    }
}

/// App state transitions recorded as breadcrumbs. Each is an enum value:
/// no host, target, network, or license text can ride along.
enum StateBreadcrumb: String, Sendable, CaseIterable {
    case setupStarted = "setup.started"
    case setupAwaitingApproval = "setup.awaiting_approval"
    case setupSucceeded = "setup.succeeded"
    case setupFailed = "setup.failed"
    case repairStarted = "repair.started"
    case repairSucceeded = "repair.succeeded"
    case repairFailed = "repair.failed"
    case protectionEnableRequested = "protection.enable_requested"
    case protectionEnabled = "protection.enabled"
    case protectionEnableFailed = "protection.enable_failed"
    case protectionDisableRequested = "protection.disable_requested"
    case protectionDisabled = "protection.disabled"
    case protectionDisableFailed = "protection.disable_failed"
    case helperConnectionInterrupted = "helper.connection_interrupted"
    case helperConnectionLost = "helper.connection_lost"

    static let categoryPrefix = "app."

    /// `app.setup`, `app.repair`, `app.protection`, or `app.helper`.
    var category: String {
        Self.categoryPrefix + String(rawValue.prefix(while: { $0 != "." }))
    }

    /// The only breadcrumb categories the SDK may send.
    static let allowedCategories: Set<String> = Set(allCases.map(\.category))

    /// Whether a breadcrumb with this category and message is one of ours.
    static func isAllowed(category: String, message: String?) -> Bool {
        guard allowedCategories.contains(category), let message else { return false }
        return StateBreadcrumb(rawValue: message)?.category == category
    }
}

/// What the helper monitor hands to the crash reporter.
enum HelperTelemetrySignal: Sendable, Equatable {
    case breadcrumb(StateBreadcrumb)
    case problem(HelperProblemReport)
}

/// Keeps one bad session from flooding the project. A fingerprint is sent
/// at most once per `minimumInterval`, and a process sends at most
/// `sessionCap` helper events in total. Main-thread confined by its owner.
struct DiagnosticEventRateLimiter {
    let minimumInterval: TimeInterval
    let sessionCap: Int
    private var lastSent: [String: TimeInterval] = [:]
    private(set) var sentCount = 0

    init(minimumInterval: TimeInterval = 30 * 60, sessionCap: Int = 10) {
        self.minimumInterval = minimumInterval
        self.sessionCap = sessionCap
    }

    /// Records the send when allowed. `now` is monotonic system uptime.
    mutating func shouldSend(key: String, now: TimeInterval) -> Bool {
        guard sentCount < sessionCap else { return false }
        if let last = lastSent[key], now - last < minimumInterval {
            return false
        }
        lastSent[key] = now
        sentCount += 1
        return true
    }
}

/// Release and environment names shared with release.sh.
enum DiagnosticRelease {
    static let bundleIdentifier = "com.amesvt.pingwarden"

    /// Matches `sentry_release_for_app` in scripts/release_validation.sh.
    static func releaseName(shortVersion: String, build: String) -> String {
        "\(bundleIdentifier)@\(shortVersion)+\(build)"
    }

    /// `development` for Debug builds, `beta` for pre-release versions or
    /// a Mac on the beta update channel, and `production` otherwise.
    static func environment(shortVersion: String, betaChannelEnabled: Bool, isDebugBuild: Bool) -> String {
        if isDebugBuild { return "development" }
        if betaChannelEnabled || isPrerelease(shortVersion) { return "beta" }
        return "production"
    }

    /// release.sh requires alpha, beta, or rc versions such as 4.4.0-beta.1.
    static func isPrerelease(_ shortVersion: String) -> Bool {
        let lowered = shortVersion.lowercased()
        return lowered.contains("-")
            || lowered.contains("alpha")
            || lowered.contains("beta")
            || lowered.contains("rc")
    }
}

/// Last-line text scrubbing for strings the SDK collects on its own, such
/// as an uncaught exception's reason. Ping Warden never puts these values in
/// events itself; this catches text from system frameworks.
enum DiagnosticScrubber {
    static let redactedURL = "<url>"
    static let redactedEmail = "<email>"
    static let redactedIP = "<ip>"
    static let redactedHost = "<host>"
    static let redactedUser = "<user>"

    /// Name extensions that look like host names but are code or bundle
    /// names, kept so stack-related text stays useful.
    private static let codeSuffixes: Set<String> = [
        "swift", "m", "mm", "h", "c", "cpp", "hpp", "plist", "framework",
        "dylib", "xpc", "appex", "bundle", "nib", "xib", "storyboard",
        "json", "xml", "txt", "log", "strings", "dmg", "zip",
    ]

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+"#
    )
    private static let emailPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )
    private static let homePathPattern = try! NSRegularExpression(
        pattern: #"/Users/[^/\s"']+"#
    )
    private static let ipv6Pattern = try! NSRegularExpression(
        pattern: #"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}(?![0-9A-Za-z:])|(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{1,4}:){1,7}:(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,6})?(?![0-9A-Za-z:])|(?<![0-9A-Za-z:])::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4}){0,6})(?![0-9A-Za-z:])"#
    )
    private static let ipv4Pattern = try! NSRegularExpression(
        pattern: #"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])"#
    )
    private static let hostPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+([A-Za-z]{2,63})(?![A-Za-z0-9_-])"#
    )

    /// Redacts URLs, email addresses, home-folder user names, IP addresses,
    /// and host names from free text.
    static func scrub(_ text: String) -> String {
        var result = text
        result = replace(urlPattern, in: result, with: redactedURL)
        result = replace(emailPattern, in: result, with: redactedEmail)
        result = scrubPath(result)
        result = replace(ipv6Pattern, in: result, with: redactedIP)
        result = replace(ipv4Pattern, in: result, with: redactedIP)
        result = replaceHosts(in: result)
        return result
    }

    /// Replaces the account name in `/Users/<name>` paths, which binary
    /// image paths carry when the app runs from a home folder.
    static func scrubPath(_ path: String) -> String {
        replace(homePathPattern, in: path, with: "/Users/\(redactedUser)")
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: template)
        )
    }

    private static func replaceHosts(in text: String) -> String {
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in hostPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let suffix = nsText.substring(with: match.range(at: 1)).lowercased()
            guard !codeSuffixes.contains(suffix) else { continue }
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += redactedHost
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }
}
