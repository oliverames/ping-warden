// Runs the actual CrashReporter and CrashReportingPolicy with a fake SDK.
// The preference adapter uses a unique test domain, never app preferences.
import Foundation
import Sentry

final class PingWardenPreferences {
    static let shared = PingWardenPreferences()
    // An absolute-path suite keeps its plist in a temporary folder
    // instead of leaving an empty file in ~/Library/Preferences.
    private let suiteName = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("com.amesvt.pingwarden.tests.crash-reporter.\(UUID().uuidString)").path
    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: suiteName)!
        CrashReportingPolicy.registerDefault(in: defaults)
    }

    var isCrashReportingEnabled: Bool {
        get { defaults.bool(forKey: CrashReportingPolicy.preferenceKey) }
        set { defaults.set(newValue, forKey: CrashReportingPolicy.preferenceKey) }
    }

    // In memory. The reporter must ignore it: the update-feed preference
    // doesn't say which build is running.
    var betaChannelEnabled = true

    func reset(storedChoice: Bool? = nil) {
        defaults.removePersistentDomain(forName: suiteName)
        if let storedChoice {
            defaults.set(storedChoice, forKey: CrashReportingPolicy.preferenceKey)
        }
        CrashReportingPolicy.registerDefault(in: defaults)
    }

    func prepareForRemoval() {
        CrashReportingPolicy.prepareForRemoval(in: defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func removeFixturePreferences() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@main
@MainActor
struct CrashReporterTests {
    static var checks = 0
    static var failures = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }

    static let rateLimitSuite = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("com.amesvt.pingwarden.tests.crash-rate-limit.\(UUID().uuidString)").path

    static func main() {
        let rateLimitDefaults = UserDefaults(suiteName: rateLimitSuite)!
        CrashReporter.rateLimitDefaults = rateLimitDefaults
        defer { rateLimitDefaults.removePersistentDomain(forName: rateLimitSuite) }
        let preferences = PingWardenPreferences.shared
        preferences.reset()
        SentrySDK.reset()
        check(preferences.isCrashReportingEnabled, "missing preference defaults on")
        var sessionStartPosts = 0
        let sessionObserver = NotificationCenter.default.addObserver(
            forName: CrashReporter.sessionStartNotification, object: nil, queue: nil
        ) { _ in sessionStartPosts += 1 }
        CrashReporter.startIfEnabled()
        NotificationCenter.default.removeObserver(sessionObserver)
        check(sessionStartPosts == 1, "enabled startup starts one release-health session")
        check(SentrySDK.startCount == 1, "default-on startup initializes SDK")
        check(SentrySDK.isActive, "SDK is active after enabled startup")
        check(!CrashReporter.relaunchRequired, "enabled launch has no pending relaunch")

        if let options = SentrySDK.lastOptions {
            check(options.releaseName == "com.amesvt.pingwarden@9.8.7+98765", "release includes bundle version and build")
            check(options.dist == "98765", "dist is the build number")
            #if DEBUG
            check(options.environment == "development", "Debug builds report under the development environment")
            #else
            check(options.environment == "production", "production environment is retained")
            #endif
            check(options.dsn?.hasPrefix("https://") == true, "DSN is configured")
            check(!options.debug, "SDK debug logging stays off")
            check(!options.sendDefaultPii, "default personal data stays off")
            check(options.tracesSampleRate?.doubleValue == 0, "performance tracing stays off")
            check(!options.enableAutoPerformanceTracing, "automatic performance spans stay off")
            check(!options.enableCoreDataTracing, "Core Data spans stay off")
            check(options.enableCrashHandler, "crash handling remains enabled")
            check(options.enableUncaughtNSExceptionReporting, "uncaught NSExceptions are reported")
            check(options.enableAutoSessionTracking, "release-health session tracking is on")
            check(options.sessionTrackingIntervalMillis == UInt.max, "reactivation never splits a run into a second session")
            check(!options.enableNetworkTracking, "network tracking stays off")
            check(!options.enableNetworkBreadcrumbs, "network breadcrumbs stay off")
            check(!options.enableCaptureFailedRequests, "failed-request events stay off")
            check(!options.enableAutoBreadcrumbTracking, "automatic UI and system breadcrumbs stay off")
            check(!options.attachStacktrace, "non-crash events carry no stack or image paths")
            check(!options.enableAppHangTracking, "hang tracking stays off")
            check(!options.enableFileIOTracing, "file tracing stays off")
            check(!options.enableMetricKit, "MetricKit payloads stay off")
            check(!options.enableLogs, "log forwarding stays off")
            check(options.beforeSend != nil, "event gate is installed")
            check(options.beforeBreadcrumb != nil, "breadcrumb filter is installed")
            let event = Event()
            check(options.beforeSend?(event) === event, "enabled gate preserves event")

            checkBreadcrumbFilter(options)
            checkScrubbing(options)
            checkHelperEvents()
            checkOrderedSubmission()
            checkLocalIdentifiers(options)
            #if DEBUG
            checkDeliveryTest()
            #endif

            // Exercise the race guard independently of closing the SDK.
            preferences.isCrashReportingEnabled = false
            check(options.beforeSend?(event) == nil, "stored opt-out immediately suppresses an in-flight event")
            CrashReporter.stop()
            check(SentrySDK.closeCount == 1, "stop closes the SDK")
            check(!SentrySDK.isActive, "SDK stops after opt-out")
            check(!CrashReporter.relaunchRequired, "opt-out clears pending relaunch")
            preferences.isCrashReportingEnabled = true
            check(CrashReporter.relaunchRequired, "opt-in after SDK close needs relaunch")
            let recreatedPaneStatus = { CrashReporter.relaunchRequired }
            check(recreatedPaneStatus(), "a recreated pane still observes pending relaunch")
            check(!SentrySDK.isActive, "pending opt-in never starts the SDK")
            preferences.isCrashReportingEnabled = false
            check(options.beforeSend?(event) == nil, "captured gate still rejects after SDK close")

            preferences.prepareForRemoval()
            check(!preferences.isCrashReportingEnabled, "removing persisted values does not re-enable the departing process")
            check(options.beforeSend?(event) == nil, "removal keeps the event gate closed")
        } else {
            check(false, "SDK received production options")
        }

        preferences.reset(storedChoice: false)
        SentrySDK.reset()
        check(!preferences.isCrashReportingEnabled, "saved opt-out survives default registration")
        CrashReporter.startIfEnabled()
        check(SentrySDK.startCount == 0, "saved opt-out prevents SDK initialization")
        check(SentrySDK.lastOptions == nil, "opted-out startup does not configure an SDK")
        CrashReporter.stop()
        check(SentrySDK.closeCount == 1, "stop is safe even when SDK was not initialized")

        // Changing the preference alone does not initialize the SDK mid-session.
        preferences.isCrashReportingEnabled = true
        check(SentrySDK.startCount == 0, "opting back in waits for the next startup call")
        check(CrashReporter.relaunchRequired, "opt-in from disabled launch stays pending")
        CrashReporter.startIfEnabled()
        check(SentrySDK.startCount == 1, "next startup honors saved opt-in")
        check(SentrySDK.isActive, "SDK starts on subsequent enabled launch")
        check(!CrashReporter.relaunchRequired, "subsequent startup clears pending status")
        CrashReporter.stop()

        // Nothing is recorded while reporting is off, including when an SDK
        // is active that CrashReporter did not start in this process.
        preferences.reset(storedChoice: false)
        SentrySDK.reset()
        CrashReporter.startIfEnabled()
        CrashReporter.resetRateLimiter()
        let report = HelperProblemReport(problem: .repairFailed, helperState: .enabled, failure: .timedOut)
        CrashReporter.record(.problem(report))
        CrashReporter.record(.breadcrumb(.repairFailed))
        check(SentrySDK.capturedEvents.isEmpty && SentrySDK.breadcrumbs.isEmpty, "opted-out process records nothing")
        SentrySDK.start { _ in }
        preferences.isCrashReportingEnabled = true
        CrashReporter.record(.problem(report))
        CrashReporter.record(.breadcrumb(.repairFailed))
        check(SentrySDK.capturedEvents.isEmpty && SentrySDK.breadcrumbs.isEmpty,
              "an opt-in pending relaunch records nothing")
        SentrySDK.close()
        preferences.removeFixturePreferences()

        rateLimitDefaults.removePersistentDomain(forName: rateLimitSuite)
        print("Crash reporter tests: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func checkBreadcrumbFilter(_ options: Options) {
        let ours = Breadcrumb(level: .info, category: StateBreadcrumb.repairStarted.category)
        ours.message = StateBreadcrumb.repairStarted.rawValue
        check(options.beforeBreadcrumb?(ours) === ours, "state breadcrumbs pass the filter")
        let ui = Breadcrumb(level: .info, category: "ui.click")
        ui.message = "Clicked Add Target"
        check(options.beforeBreadcrumb?(ui) == nil, "UI breadcrumbs are dropped")
        let forged = Breadcrumb(level: .info, category: StateBreadcrumb.repairStarted.category)
        forged.message = "probe.example.com"
        check(options.beforeBreadcrumb?(forged) == nil, "free text in an allowed category is dropped")
        let mismatched = Breadcrumb(level: .info, category: "app.setup")
        mismatched.message = StateBreadcrumb.repairStarted.rawValue
        check(options.beforeBreadcrumb?(mismatched) == nil, "a value under the wrong category is dropped")
    }

    static func checkScrubbing(_ options: Options) {
        let inBundle = CrashReporter.bundlePath + "/Contents/MacOS/Ping Warden"
        let elsewhere = "/Users/Oliver/Applications/Other Tool.app/Contents/MacOS/Other Tool"
        let systemImage = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
        let dataVolume = "/System/Volumes/Data/Users/jane/lib/libhelper.dylib"
        let event = Event(level: .fatal)
        event.serverName = "Olivers-MacBook-Pro.local"
        event.user = User(userId: "installation-id")
        event.extra = ["note": "probe.example.com"]
        event.transaction = "SettingsView"
        event.modules = ["Sentry": "9.26.0"]
        event.tags = ["sdk_tag": "x"]
        event.context = [
            "device": ["name": "Oliver's MacBook Pro", "model": "Mac15,3", "memory_size": 17179869184, "boot_time": "2026-10-14"],
            "os": ["name": "macOS", "version": "15.5", "kernel_version": "Darwin 24.5.0"],
            "app": ["app_version": "9.8.7", "app_build": "98765", "device_app_hash": "abc123", "app_start_time": "2026-10-14"],
            "culture": ["locale": "en_US", "timezone": "America/New_York", "calendar": "gregorian"],
            "trace": ["trace_id": "0123"],
        ]
        event.message = SentryMessage(formatted: "Failed to reach 192.0.2.10 via game.example.net")
        let exception = Exception(
            value: "-[NSURL host]: anything at all, even relay.xn--p1ai or ::",
            type: "NSInvalidArgumentException"
        )
        let mechanism = Mechanism(type: "nsexception")
        mechanism.desc = "reason with probe.example.com"
        mechanism.data = ["reason": "probe.example.com"]
        mechanism.helpLink = "https://example.com/help"
        exception.mechanism = mechanism
        let frames = [inBundle, elsewhere, systemImage, dataVolume].map { path -> Frame in
            let frame = Frame()
            frame.package = path
            frame.fileName = path
            frame.function = "-[NSApplication run]"
            frame.contextLine = "let host = \"probe.example.com\""
            frame.preContext = ["a"]
            frame.postContext = ["b"]
            frame.vars = ["host": "probe.example.com"]
            return frame
        }
        exception.stacktrace = SentryStacktrace(frames: frames)
        event.exceptions = [exception]
        let thread = SentryThread()
        thread.name = "probe.example.com worker"
        let threadFrame = Frame()
        threadFrame.package = elsewhere
        thread.stacktrace = SentryStacktrace(frames: [threadFrame])
        event.threads = [thread]
        let images = [inBundle, elsewhere, systemImage].map { path -> DebugMeta in
            let image = DebugMeta()
            image.codeFile = path
            return image
        }
        event.debugMeta = images
        let ours = Breadcrumb(level: .info, category: StateBreadcrumb.protectionEnabled.category)
        ours.message = StateBreadcrumb.protectionEnabled.rawValue
        let foreign = Breadcrumb(level: .info, category: "http")
        foreign.message = "GET https://api.gumroad.com/v2/licenses/verify"
        event.breadcrumbs = [ours, foreign]

        guard let sent = options.beforeSend?(event) else {
            check(false, "enabled gate keeps a crash event")
            return
        }
        check(sent.serverName == nil, "server name is removed")
        check(sent.user == nil, "event user is removed")
        check(sent.extra == nil && sent.transaction == nil && sent.modules == nil, "extra data, transaction, and modules are removed")
        check(sent.message == nil, "crash messages are removed, not filtered")
        check(sent.tags == nil && sent.fingerprint == nil, "SDK tags and fingerprints are removed from crash events")
        check(Set(sent.context?.keys.map { $0 } ?? []) == ["device", "os", "app"], "only disclosed contexts remain: \(sent.context?.keys.sorted() ?? [])")
        check(Set(sent.context?["device"]?.keys.map { $0 } ?? []) == ["model"], "device keeps only disclosed keys")
        check(Set(sent.context?["os"]?.keys.map { $0 } ?? []) == ["name", "version"], "os keeps only disclosed keys")
        check(Set(sent.context?["app"]?.keys.map { $0 } ?? []) == ["app_version", "app_build"], "app keeps only version and build")
        let sentException = sent.exceptions?.first
        check(sentException?.value == nil, "exception messages are removed, not filtered")
        check(sentException?.type == "NSInvalidArgumentException", "exception type is kept")
        check(sentException?.mechanism?.type == "nsexception", "mechanism type is kept")
        check(sentException?.mechanism?.desc == nil && sentException?.mechanism?.data == nil && sentException?.mechanism?.helpLink == nil,
              "mechanism text is removed")
        let sentFrames = sentException?.stacktrace?.frames ?? []
        check(sentFrames.map { $0.package } == [
            "Ping Warden.app/Contents/MacOS/Ping Warden",
            "Other Tool",
            systemImage,
            "libhelper.dylib",
        ], "frame paths are reduced to bundle-relative, system, or file name: \(sentFrames.map { $0.package })")
        check(sentFrames.map { $0.fileName } == sentFrames.map { $0.package }, "frame file names are reduced the same way")
        check(sentFrames.allSatisfy { $0.function == "-[NSApplication run]" }, "function names are kept")
        check(sentFrames.allSatisfy { $0.contextLine == nil && $0.preContext == nil && $0.postContext == nil && $0.vars == nil },
              "source context and variables are removed")
        check(sent.threads?.first?.name == nil, "thread names are removed")
        check(sent.threads?.first?.stacktrace?.frames.first?.package == "Other Tool", "thread frame paths are reduced")
        check(sent.debugMeta?.map { $0.codeFile } == ["Ping Warden.app/Contents/MacOS/Ping Warden", "Other Tool", systemImage],
              "image paths are reduced: \(sent.debugMeta?.map { $0.codeFile } ?? [])")
        check(sent.breadcrumbs?.map { $0.message } == [StateBreadcrumb.protectionEnabled.rawValue],
              "only state breadcrumbs remain on events")

        // Ping Warden's own events keep their enum-built message and tags.
        let own = Event(level: .warning)
        own.message = SentryMessage(formatted: "Helper problem: repair_failed")
        own.fingerprint = ["helper-problem", "repair_failed", "timed_out", "none", "none"]
        own.tags = ["helper_problem": "repair_failed"]
        let sentOwn = options.beforeSend?(own)
        check(sentOwn?.message?.formatted == "Helper problem: repair_failed" && sentOwn?.tags?["helper_problem"] == "repair_failed",
              "helper events keep their fixed message and tags")
    }

    static func checkHelperEvents() {
        SentrySDK.reset()
        // Reinstall the production options on the fixture SDK.
        CrashReporter.startIfEnabled()
        var clock: TimeInterval = 1_000
        CrashReporter.now = { clock }
        CrashReporter.resetRateLimiter(DiagnosticEventRateLimiter(minimumInterval: 60, sessionCap: 3))

        CrashReporter.record(.breadcrumb(.setupStarted))
        check(SentrySDK.breadcrumbs.map(\.category) == ["app.setup"], "state breadcrumbs reach the SDK")
        check(SentrySDK.breadcrumbs.first?.message == "setup.started", "breadcrumb message is the enum value")

        let timeout = HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .timedOut)
        CrashReporter.record(.problem(timeout))
        check(SentrySDK.capturedEvents.count == 1, "a helper problem is captured")
        if let event = SentrySDK.capturedEvents.first {
            check(event.level == .warning, "helper problems are warnings, not crashes")
            check(event.message?.formatted == "Helper problem: protection_enable_failed", "message is the fixed problem name")
            check(event.fingerprint == ["helper-problem", "protection_enable_failed", "timed_out", "none", "none"], "fingerprint is stable")
            let tags = event.tags ?? [:]
            check(Set(tags.keys) == ["helper_problem", "helper_state", "failure_reason", "app_version", "macos_version"],
                  "only allowlisted tags are set: \(tags.keys.sorted())")
            check(tags["app_version"] == "9.8.7" && tags["helper_state"] == "enabled", "tags carry app version and helper state")
            check(tags["macos_version"]?.split(separator: ".").count == 3, "macOS version is major.minor.patch")
        }

        CrashReporter.record(.problem(timeout))
        check(SentrySDK.capturedEvents.count == 1, "a repeated problem inside the interval is dropped")
        clock += 61
        CrashReporter.record(.problem(timeout))
        check(SentrySDK.capturedEvents.count == 2, "the same problem is sent again after the interval")
        let declined = HelperProblemReport(problem: .protectionEnableFailed, helperState: .enabled, failure: .declined)
        CrashReporter.record(.problem(declined))
        check(SentrySDK.capturedEvents.count == 2, "a different reason for the same problem shares its rate limit")
        let rejected = HelperProblemReport(problem: .repairFailed, helperState: .notFound, failure: .rejected(code: 4099))
        CrashReporter.record(.problem(rejected))
        check(SentrySDK.capturedEvents.last?.tags?["error_domain"] == NSCocoaErrorDomain
              && SentrySDK.capturedEvents.last?.tags?["error_code"] == "4099", "XPC errors report Cocoa domain and code")
        clock += 1_000
        CrashReporter.record(.problem(HelperProblemReport(problem: .helperConnectionLost, helperState: .enabled)))
        check(SentrySDK.capturedEvents.count == 3, "the per-run cap stops a flood")

        // A relaunch loads the saved send times, so the 30-minute limit holds.
        let saved = DiagnosticRateLimitStore.load(from: CrashReporter.rateLimitDefaults)
        check(Set(saved.keys) == ["protection_enable_failed", "repair_failed"], "send times persist per problem: \(saved)")
        CrashReporter.resetRateLimiter(DiagnosticEventRateLimiter(
            minimumInterval: 2_000,
            sessionCap: 3,
            lastSent: DiagnosticRateLimitStore.load(from: CrashReporter.rateLimitDefaults)
        ))
        CrashReporter.record(.problem(rejected))
        check(SentrySDK.capturedEvents.count == 3, "a relaunched process still honors the saved limit")
        CrashReporter.record(.problem(HelperProblemReport(problem: .helperUnresponsive, helperState: .enabled)))
        check(SentrySDK.capturedEvents.count == 4, "a relaunch starts a fresh per-run cap")

        PingWardenPreferences.shared.isCrashReportingEnabled = false
        CrashReporter.resetRateLimiter()
        CrashReporter.record(.problem(rejected))
        CrashReporter.record(.breadcrumb(.repairStarted))
        check(SentrySDK.capturedEvents.count == 4 && SentrySDK.breadcrumbs.count == 1,
              "turning reporting off stops helper events and breadcrumbs immediately")
        PingWardenPreferences.shared.isCrashReportingEnabled = true
        CrashReporter.now = { Date().timeIntervalSince1970 }
        CrashReporter.resetRateLimiter()
    }

    /// Signals raised off the main actor arrive in the order they were raised.
    static func checkOrderedSubmission() {
        SentrySDK.reset()
        CrashReporter.startIfEnabled()
        CrashReporter.resetRateLimiter()
        let problems: [HelperProblem] = [.repairFailed, .registrationFailed, .protectionDisableFailed, .helperUnresponsive]
        var expected: [String] = []
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for problem in problems {
                CrashReporter.submit(.breadcrumb(.repairStarted))
                CrashReporter.submit(.problem(HelperProblemReport(problem: problem, helperState: .enabled, failure: .timedOut)))
            }
            done.signal()
        }
        done.wait()
        for problem in problems {
            expected.append("breadcrumb:repair.started")
            expected.append("event:Helper problem: \(problem.rawValue)")
        }
        let deadline = Date().addingTimeInterval(2)
        while SentrySDK.arrivals.count < expected.count && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(SentrySDK.arrivals == expected, "submitted signals keep their order: \(SentrySDK.arrivals)")
        CrashReporter.resetRateLimiter()
    }

    /// This Mac's own account and computer names are removed from SDK text.
    static func checkLocalIdentifiers(_ options: Options) {
        let names = CrashReporter.localIdentifiers.filter { $0.count >= 3 }
        check(names.contains(NSUserName()), "the account name is a known identifier")
        guard let name = names.first else { return }
        let event = Event(level: .fatal)
        let exception = Exception(value: nil, type: "Error\(name.uppercased())Exception")
        event.exceptions = [exception]
        guard let sent = options.beforeSend?(event) else {
            check(false, "enabled gate keeps the identifier event")
            return
        }
        check(sent.exceptions?.first?.type == "Error<name>Exception",
              "defense in depth removes this Mac's names from the remaining type text: \(sent.exceptions?.first?.type ?? "")")
    }

    #if DEBUG
    static func checkDeliveryTest() {
        let before = SentrySDK.capturedEvents.count
        CrashReporter.sendDeliveryTestEvent()
        check(SentrySDK.capturedEvents.count == before + 1, "Debug delivery test sends one event")
        check(SentrySDK.capturedEvents.last?.fingerprint == CrashReporter.deliveryTestFingerprint, "delivery test groups as one issue")
        check(SentrySDK.capturedEvents.last?.tags?["delivery_test"] == "true", "delivery test is tagged")
        check(SentrySDK.flushCount == 1, "delivery test flushes before returning")
    }
    #endif
}
