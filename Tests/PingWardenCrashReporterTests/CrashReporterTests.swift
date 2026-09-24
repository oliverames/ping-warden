// Runs the actual CrashReporter and CrashReportingPolicy with a fake SDK.
// The preference adapter uses a unique test domain, never app preferences.
import Foundation
import Sentry

final class PingWardenPreferences {
    static let shared = PingWardenPreferences()
    private let suiteName = "com.amesvt.pingwarden.tests.crash-reporter.\(UUID().uuidString)"
    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: suiteName)!
        CrashReportingPolicy.registerDefault(in: defaults)
    }

    var isCrashReportingEnabled: Bool {
        get { defaults.bool(forKey: CrashReportingPolicy.preferenceKey) }
        set { defaults.set(newValue, forKey: CrashReportingPolicy.preferenceKey) }
    }

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

    static func main() {
        let preferences = PingWardenPreferences.shared
        preferences.reset()
        SentrySDK.reset()
        check(preferences.isCrashReportingEnabled, "missing preference defaults on")
        CrashReporter.startIfEnabled()
        check(SentrySDK.startCount == 1, "default-on startup initializes SDK")
        check(SentrySDK.isActive, "SDK is active after enabled startup")
        check(!CrashReporter.relaunchRequired, "enabled launch has no pending relaunch")

        if let options = SentrySDK.lastOptions {
            check(options.releaseName == "com.amesvt.pingwarden@9.8.7+98765", "release includes bundle version and build")
            check(options.environment == "production", "production environment is retained")
            check(options.dsn?.hasPrefix("https://") == true, "DSN is configured")
            check(!options.debug, "SDK debug logging stays off")
            check(!options.sendDefaultPii, "default personal data stays off")
            check(options.tracesSampleRate?.doubleValue == 0, "performance tracing stays off")
            check(options.enableCrashHandler, "crash handling remains enabled")
            check(!options.enableAutoSessionTracking, "session tracking stays off")
            check(!options.enableNetworkTracking, "network tracking stays off")
            check(!options.enableNetworkBreadcrumbs, "network breadcrumbs stay off")
            check(!options.enableCaptureFailedRequests, "failed-request events stay off")
            check(!options.enableAppHangTracking, "hang tracking stays off")
            check(!options.enableFileIOTracing, "file tracing stays off")
            check(options.beforeSend != nil, "event gate is installed")
            let event = Event()
            check(options.beforeSend?(event) === event, "enabled gate preserves event")

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
        preferences.removeFixturePreferences()

        print("Crash reporter tests: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
