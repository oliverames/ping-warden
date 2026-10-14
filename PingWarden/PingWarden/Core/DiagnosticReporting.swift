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

    /// Rate-limit key: one event per problem per interval, whatever its
    /// reason or error code, so the disclosed "one per problem" holds.
    var rateLimitKey: String { problem.rawValue }

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

/// Keeps one bad session from flooding the project. A key (one per
/// `HelperProblem`) is sent at most once per `minimumInterval`, and a
/// process sends at most
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

    /// Info.plist key holding the channel the artifact was built for.
    /// release.sh archives with `PING_WARDEN_RELEASE_CHANNEL=beta` for
    /// `BETA_CHANNEL=1` releases; the project default is `production`.
    /// The marketing version can't carry this: release validation requires
    /// it without the pre-release suffix.
    static let releaseChannelInfoKey = "PingWardenReleaseChannel"

    /// `development` for Debug builds, `beta` for an artifact built for the
    /// beta channel, and `production` otherwise. The person's beta-update
    /// preference is deliberately ignored: it says which feed they follow,
    /// not which build is running.
    static func environment(releaseChannel: String?, isDebugBuild: Bool) -> String {
        if isDebugBuild { return "development" }
        if releaseChannel?.trimmingCharacters(in: .whitespaces).lowercased() == "beta" { return "beta" }
        return "production"
    }
}

/// The event contexts and keys that may leave the Mac, matching the
/// disclosure: app version and build, macOS name, version, and build, and
/// the Mac's model family, model, and architecture. Everything else the SDK
/// gathers (the culture context's locale, time zone, and calendar; device
/// memory, boot time, and name; the app's device hash and start time; trace
/// identifiers) is removed.
enum DiagnosticContextPolicy {
    static let allowedKeys: [String: Set<String>] = [
        "app": ["app_version", "app_build"],
        "os": ["name", "version", "build"],
        "device": ["family", "model", "arch"],
    ]

    static func filter(_ contexts: [String: [String: Any]]) -> [String: [String: Any]] {
        var kept: [String: [String: Any]] = [:]
        for (name, values) in contexts {
            guard let allowed = allowedKeys[name] else { continue }
            let filtered = values.filter { allowed.contains($0.key) }
            if !filtered.isEmpty { kept[name] = filtered }
        }
        return kept
    }
}

/// Last-line text scrubbing for strings the SDK collects on its own, such
/// as an uncaught exception's reason. Ping Warden never puts these values in
/// events itself; this catches text from system frameworks.
///
/// Passes run in a fixed order, because each one removes text a later,
/// looser pass could otherwise split and half-redact:
///   1. this Mac's own account, full, and computer names (`<name>`)
///   2. URLs with a scheme (`<url>`) and email addresses (`<email>`)
///   3. home folders: this account's, `/Users/<name>`, `/home/<name>`,
///      `~name`, and Windows `C:\Users\<name>` paths
///   4. IPv6 with an embedded IPv4 (`::ffff:192.0.2.1`), then MAC
///      addresses (`<mac>`), then IPv6 with optional zone, then IPv4 (`<ip>`)
///   5. host names, including Unicode and punycode TLDs, with any port and
///      path that follows (`<host>`), which also covers scheme-less URLs
enum DiagnosticScrubber {
    static let redactedURL = "<url>"
    static let redactedEmail = "<email>"
    static let redactedIP = "<ip>"
    static let redactedMAC = "<mac>"
    static let redactedHost = "<host>"
    static let redactedUser = "<user>"
    static let redactedName = "<name>"

    /// Name extensions that look like host names but are code or bundle
    /// names, kept so stack-related text stays useful. None of these is a
    /// delegated top-level domain (checked against the IANA root zone list
    /// on 2026-10-14), so a bare host name can't hide behind one. `mm` and
    /// `zip` are real TLDs and are deliberately absent.
    static let codeSuffixes: Set<String> = [
        "swift", "m", "h", "c", "cpp", "hpp", "plist", "framework",
        "dylib", "xpc", "appex", "bundle", "nib", "xib", "storyboard",
        "json", "xml", "txt", "log", "strings", "dmg",
    ]

    /// A top-level domain: Unicode letters, or an ASCII punycode label.
    private static let tld = #"(\p{L}{2,63}|[Xx][Nn]--[A-Za-z0-9-]{1,59})"#
    private static let label = #"[\p{L}\p{N}](?:[\p{L}\p{N}-]{0,61}[\p{L}\p{N}])?"#

    private static let urlPattern = regex(#"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+"#)
    private static let emailPattern = regex(#"[\p{L}\p{N}._%+-]+@(?:"# + label + #"\.)+"# + tld + #"(?![\p{L}\p{N}_-])"#)
    private static let usersPathPattern = regex(#"/(Users|home)/[^/\s"']+"#)
    private static let tildeUserPattern = regex(#"(?<![\p{L}\p{N}_/~])~[A-Za-z_][A-Za-z0-9._-]*"#)
    private static let windowsHomePattern = regex(#"(?i)\b([A-Z]):\\(Users|Documents and Settings)\\[^\\\r\n"']+"#)
    private static let mixedIPPattern = regex(
        #"(?<![0-9A-Za-z:.])(?:[0-9A-Fa-f]{0,4}:){2,6}(?:\d{1,3}\.){3}\d{1,3}(?:%[0-9A-Za-z._-]+)?(?![0-9A-Za-z.])"#
    )
    private static let macPattern = regex(
        #"(?<![0-9A-Fa-f:.-])(?:[0-9A-Fa-f]{2}([:-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}|(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4})(?![0-9A-Fa-f:.-])"#
    )
    private static let ipv6Pattern: NSRegularExpression = {
        let hex = "[0-9A-Fa-f]{1,4}"
        let zone = "(?:%[0-9A-Za-z._-]+)?"
        let before = "(?<![0-9A-Za-z:])"
        let after = "(?![0-9A-Za-z:])"
        let forms = [
            "(?:\(hex):){7}\(hex)",
            "(?:\(hex):){1,7}:(?:\(hex)(?::\(hex)){0,6})?",
            "::(?:\(hex)(?::\(hex)){0,6})",
        ]
        return regex(forms.map { before + $0 + zone + after }.joined(separator: "|"))
    }()
    private static let ipv4Pattern = regex(#"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])"#)
    private static let hostPattern = regex(
        #"(?<![\p{L}\p{N}_.-])(?:"# + label + #"\.)+"# + tld + #"(?![\p{L}\p{N}_-])(?::\d{1,5})?(?:/[^\s"'<>]*)?"#
    )

    /// Redacts identifying text as listed on the type. `knownIdentifiers`
    /// are this Mac's account and computer names; values shorter than three
    /// characters are ignored so they can't erase ordinary words.
    static func scrub(
        _ text: String,
        homeDirectory: String = NSHomeDirectory(),
        knownIdentifiers: [String] = []
    ) -> String {
        var result = text
        for identifier in knownIdentifiers.sorted(by: { $0.count > $1.count })
        where identifier.trimmingCharacters(in: .whitespaces).count >= 3 {
            result = result.replacingOccurrences(
                of: identifier,
                with: redactedName,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        result = replace(urlPattern, in: result, with: redactedURL)
        result = replace(emailPattern, in: result, with: redactedEmail)
        result = scrubPath(result, homeDirectory: homeDirectory)
        result = replace(mixedIPPattern, in: result, with: redactedIP)
        result = replace(macPattern, in: result, with: redactedMAC)
        result = replace(ipv6Pattern, in: result, with: redactedIP)
        result = replace(ipv4Pattern, in: result, with: redactedIP)
        result = replaceHosts(in: result)
        return result
    }

    /// Replaces this account's home folder with `~`, wherever it lives
    /// (network and managed homes aren't always under /Users), then the
    /// account name in any other `/Users/<name>`, `/home/<name>`, `~name`,
    /// or Windows `X:\Users\<name>` path. Binary image paths carry these
    /// when the app runs from a home folder.
    static func scrubPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var result = path
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        // A root or one-component home would redact unrelated paths.
        if home.split(separator: "/").count >= 2 {
            result = replace(
                regex(NSRegularExpression.escapedPattern(for: home) + #"(?=/|$|[\s"'])"#),
                in: result,
                with: "~"
            )
        }
        result = replaceTemplate(usersPathPattern, in: result, template: "/$1/\(redactedUser)")
        result = replace(tildeUserPattern, in: result, with: "~\(redactedUser)")
        result = replaceTemplate(windowsHomePattern, in: result, template: #"$1:\\$2\\"# + redactedUser)
        return result
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with literal: String) -> String {
        replaceTemplate(pattern, in: text, template: NSRegularExpression.escapedTemplate(for: literal))
    }

    private static func replaceTemplate(_ pattern: NSRegularExpression, in text: String, template: String) -> String {
        pattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
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
