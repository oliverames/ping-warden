// Test-only Sentry replacement. It records configuration and never sends data.
import Foundation

public final class Event {
    public init() {}
}

public final class Options {
    public var dsn: String?
    public var releaseName: String?
    public var environment: String?
    // Deliberately unsafe defaults prove production explicitly disables these.
    public var debug = true
    public var sendDefaultPii = true
    public var tracesSampleRate: NSNumber? = 1
    public var enableCrashHandler = false
    public var enableAutoSessionTracking = true
    public var enableNetworkTracking = true
    public var enableNetworkBreadcrumbs = true
    public var enableCaptureFailedRequests = true
    public var enableAppHangTracking = true
    public var enableFileIOTracing = true
    public var beforeSend: ((Event) -> Event?)?
    public init() {}
}

public enum SentrySDK {
    public private(set) static var startCount = 0
    public private(set) static var closeCount = 0
    public private(set) static var isActive = false
    public private(set) static var lastOptions: Options?

    public static func start(configureOptions: (Options) -> Void) {
        let options = Options()
        configureOptions(options)
        lastOptions = options
        startCount += 1
        isActive = true
    }

    public static func close() {
        closeCount += 1
        isActive = false
    }

    public static func reset() {
        startCount = 0
        closeCount = 0
        isActive = false
        lastOptions = nil
    }
}
