//
//  CrashReporter.swift
//  PingWarden
//
//  Anonymous crash and error reporting via Sentry. The Sentry SDK is added
//  as an SPM dependency; this file is inert (no-op) until the package is
//  linked, thanks to the `#if canImport(Sentry)` guards.
//
//  What is sent (only while Settings → Advanced → Privacy → Send Crash
//  Reports is on, which is the default when no choice is saved):
//    • Crash reports and uncaught Objective-C exceptions.
//    • Non-fatal helper error events: setup, repair, and protection on/off
//      failures and an unresponsive helper. Each carries only an enum
//      problem name, the helper's registration state, an allowlisted error
//      domain and numeric code, the app version, and the macOS version.
//      At most one per problem every 30 minutes and ten per app run.
//    • Release health: one session per app run (start, end, crashed or not)
//      with a random installation identifier created by the SDK.
//    • On every event: app version and build, macOS name, version, and
//      build, and the Mac's model family, model, and architecture. Other SDK
//      contexts (locale, time zone, calendar, memory, device name, device
//      hash) and the event user are removed in beforeSend.
//    • Breadcrumbs of app state transitions (setup, repair, protection,
//      helper connection), as enum values only.
//
//  What is never sent: ping targets, host names, IP addresses (no
//  sendDefaultPii; server-side IP scrubbing), network names, license keys,
//  usage analytics, network requests or failed-request events, file or
//  Core Data spans, screenshots, or performance traces.
//
//  Performance tracing stays off (tracesSampleRate = 0). On macOS the SDK
//  has no app-start measurement, so a launch transaction would hold only
//  the auto-instrumented spans, and those record file paths and request
//  URLs, which can carry the macOS account name or a ping target. Setup
//  duration is already visible from breadcrumb timestamps on error events.
//
//  beforeSend re-checks the preference as defense-in-depth, so a racing
//  toggle-off between SDK init and first event still suppresses, and it
//  scrubs free text the SDK collects itself (exception reasons, binary
//  image paths) through DiagnosticScrubber.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import os.log

#if canImport(Sentry)
import Sentry
#endif

private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "CrashReporter")

@MainActor
enum CrashReporter {
    // Process lifetime state survives settings-pane recreation. It is never saved.
    private static var startedThisProcess = false
    static var relaunchRequired: Bool {
        PingWardenPreferences.shared.isCrashReportingEnabled && !startedThisProcess
    }

    /// Sentry DSN. Not a secret — DSNs are designed to be embedded in
    /// distributed client binaries; Sentry enforces project-side scrubbing.
    private static let dsn = "https://3492628142810aa2deb988baaec35d0c@o4511410883985408.ingest.us.sentry.io/4511410888704000"

    /// Posting this notification is how the SDK's session tracker learns an
    /// app without a key window is in use. A menu bar app is rarely active,
    /// so without it most runs would never start a release-health session.
    static let sessionStartNotification = Notification.Name("SentryHybridSdkDidBecomeActive")

    /// Per-process limit on helper error events.
    private static var rateLimiter = DiagnosticEventRateLimiter()

    /// Monotonic clock for rate limiting; replaceable in tests.
    static var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Whether events may be sent right now: the person has not opted out
    /// and the SDK started in this process.
    static var isReporting: Bool {
        startedThisProcess && PingWardenPreferences.shared.isCrashReportingEnabled
    }

    /// Initialize Sentry if the SDK is linked and reporting is enabled.
    /// Call once at app launch, before the first opportunity for a
    /// crash. Turning reporting off is enforced immediately by `beforeSend`;
    /// turning it on requires a relaunch so the SDK can initialize cleanly.
    static func startIfEnabled() {
        guard PingWardenPreferences.shared.isCrashReportingEnabled else {
            log.info("Crash reporting opted out by user; Sentry not initialized")
            return
        }

        #if canImport(Sentry)
        let version = appVersion
        let build = buildNumber
        // The channel the artifact was built for, embedded at release time,
        // not the person's update-feed preference.
        let environment = DiagnosticRelease.environment(
            releaseChannel: Bundle.main.infoDictionary?[DiagnosticRelease.releaseChannelInfoKey] as? String,
            isDebugBuild: isDebugBuild
        )

        SentrySDK.start { options in
            options.dsn = Self.dsn
            // Matches release.sh's `sentry_release_for_app` so dSYMs and
            // release health attach to the same release.
            options.releaseName = DiagnosticRelease.releaseName(shortVersion: version, build: build)
            options.dist = build
            options.environment = environment

            options.debug = false

            options.sendDefaultPii = false

            // Crashes, including uncaught NSExceptions, which the macOS SDK
            // does not catch without this option.
            options.enableCrashHandler = true
            options.enableUncaughtNSExceptionReporting = true

            // Release health: crash-free sessions and users per release.
            // The session starts below, after SDK start. The SDK normally
            // starts a new session when the app reactivates after 30 s in
            // the background; an unreachable interval keeps it to exactly
            // one session per process, ended at quit or marked crashed on
            // the next launch.
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = UInt.max

            // No performance data. See the file header for why.
            options.tracesSampleRate = 0.0
            // Profiling is off by default in sentry-cocoa 9.x; no Options
            // property to set explicitly. Tracing must stay 0.0 above —
            // profiling is sampled as a subset of traces, so 0% tracing
            // → 0% profiling regardless.
            options.enableAutoPerformanceTracing = false
            options.enableCoreDataTracing = false
            options.enableFileIOTracing = false

            // Network activity carries update, license, and probe URLs.
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false

            // Only Ping Warden's own enum breadcrumbs, never UI or system ones.
            options.enableAutoBreadcrumbTracking = false
            options.beforeBreadcrumb = { crumb in
                Self.filterBreadcrumb(crumb)
            }

            // Helper events are grouped by fingerprint; their stack is the
            // same reporting call every time and only adds image paths.
            options.attachStacktrace = false

            options.enableAppHangTracking = false
            options.enableMetricKit = false
            options.enableLogs = false

            options.beforeSend = { event in
                guard PingWardenPreferences.shared.isCrashReportingEnabled else {
                    return nil
                }
                return Self.scrub(event)
            }
        }
        startedThisProcess = true
        NotificationCenter.default.post(name: sessionStartNotification, object: nil)
        log.info("Sentry initialized (release: \(version, privacy: .public), environment: \(environment, privacy: .public))")
        #else
        log.notice("Sentry SDK not linked; add via SPM: https://github.com/getsentry/sentry-cocoa")
        #endif
    }

    /// Stop SDK activity after the preference has been switched off. Keep
    /// beforeSend as a second check for events racing the preference change.
    static func stop() {
        startedThisProcess = false
        #if canImport(Sentry)
        SentrySDK.close()
        #endif
    }

    /// Entry point for the helper monitor, which runs off the main actor.
    nonisolated static func submit(_ signal: HelperTelemetrySignal) {
        Task { @MainActor in
            record(signal)
        }
    }

    /// Record a breadcrumb or a rate-limited helper error event. Does
    /// nothing while reporting is off or the SDK has not started.
    static func record(_ signal: HelperTelemetrySignal) {
        guard isReporting else { return }
        #if canImport(Sentry)
        switch signal {
        case .breadcrumb(let state):
            let crumb = Breadcrumb(level: .info, category: state.category)
            crumb.message = state.rawValue
            crumb.type = "info"
            SentrySDK.addBreadcrumb(crumb)
        case .problem(let report):
            guard rateLimiter.shouldSend(key: report.rateLimitKey, now: now()) else {
                log.debug("Helper problem \(report.problem.rawValue, privacy: .public) not sent: rate limited")
                return
            }
            let event = Event(level: .warning)
            event.message = SentryMessage(formatted: report.message)
            event.fingerprint = report.fingerprint
            event.tags = report.tags(appVersion: appVersion, macOSVersion: macOSVersion)
            _ = SentrySDK.capture(event: event)
        }
        #endif
    }

    /// Clear the per-process rate limit. Tests only.
    static func resetRateLimiter(_ limiter: DiagnosticEventRateLimiter = DiagnosticEventRateLimiter()) {
        rateLimiter = limiter
    }

    #if canImport(Sentry)
    /// Keep only breadcrumbs that are one of `StateBreadcrumb`'s values.
    nonisolated static func filterBreadcrumb(_ crumb: Breadcrumb) -> Breadcrumb? {
        StateBreadcrumb.isAllowed(category: crumb.category, message: crumb.message) ? crumb : nil
    }

    /// Remove machine and free-text details the SDK gathers on its own.
    nonisolated static func scrub(_ event: Event) -> Event {
        event.serverName = nil
        event.user = nil
        if let context = event.context {
            let kept = DiagnosticContextPolicy.filter(context)
            event.context = kept.isEmpty ? nil : kept
        }
        if let message = event.message {
            event.message = SentryMessage(formatted: DiagnosticScrubber.scrub(message.formatted))
        }
        for exception in event.exceptions ?? [] {
            exception.value = exception.value.map { DiagnosticScrubber.scrub($0) }
            scrubFrames(exception.stacktrace)
        }
        for thread in event.threads ?? [] {
            scrubFrames(thread.stacktrace)
        }
        for image in event.debugMeta ?? [] {
            image.codeFile = image.codeFile.map { DiagnosticScrubber.scrubPath($0) }
        }
        if let breadcrumbs = event.breadcrumbs {
            event.breadcrumbs = breadcrumbs.filter {
                StateBreadcrumb.isAllowed(category: $0.category, message: $0.message)
            }
        }
        return event
    }

    nonisolated private static func scrubFrames(_ stacktrace: SentryStacktrace?) {
        for frame in stacktrace?.frames ?? [] {
            frame.package = frame.package.map { DiagnosticScrubber.scrubPath($0) }
        }
    }
    #endif

    #if DEBUG
    /// The fingerprint of the delivery check, so it groups as one issue.
    static let deliveryTestFingerprint = ["delivery-verification"]

    /// Send one event that proves the DSN path end to end. Debug builds
    /// only (environment `development`), started with the launch argument
    /// `--sentry-test-event`. See CONTRIBUTING.md for checking receipt.
    static func sendDeliveryTestEvent() {
        guard isReporting else {
            log.notice("Sentry delivery test skipped: reporting is off")
            return
        }
        #if canImport(Sentry)
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: "Delivery verification")
        event.fingerprint = deliveryTestFingerprint
        event.tags = [
            "delivery_test": "true",
            "app_version": appVersion,
            "macos_version": macOSVersion,
        ]
        let eventID = SentrySDK.capture(event: event)
        SentrySDK.flush(timeout: 5)
        log.notice("Sentry delivery test sent: \(String(describing: eventID), privacy: .public)")
        #endif
    }
    #endif
}
