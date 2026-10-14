// Test-only Sentry replacement. It records configuration and captured
// events and never sends data. Names and shapes follow sentry-cocoa 9.x as
// seen from Swift.
import Foundation

public enum SentryLevel: UInt {
    case none, debug, info, warning, error, fatal
}

public final class SentryMessage {
    public let formatted: String
    public var message: String?
    public init(formatted: String) { self.formatted = formatted }
}

public final class Frame {
    public var package: String?
    public var function: String?
    public init() {}
}

public final class SentryStacktrace {
    public var frames: [Frame]
    public init(frames: [Frame]) { self.frames = frames }
}

public final class Exception {
    public var value: String?
    public var type: String?
    public var stacktrace: SentryStacktrace?
    public init(value: String?, type: String?) {
        self.value = value
        self.type = type
    }
}

public final class SentryThread {
    public var stacktrace: SentryStacktrace?
    public init() {}
}

public final class DebugMeta {
    public var codeFile: String?
    public init() {}
}

public final class Breadcrumb {
    public var level: SentryLevel
    public var category: String
    public var message: String?
    public var type: String?
    public init(level: SentryLevel, category: String) {
        self.level = level
        self.category = category
    }
}

public final class Event {
    public var level: SentryLevel
    public var message: SentryMessage?
    public var serverName: String?
    public var tags: [String: String]?
    public var fingerprint: [String]?
    public var context: [String: [String: Any]]?
    public var exceptions: [Exception]?
    public var threads: [SentryThread]?
    public var debugMeta: [DebugMeta]?
    public var breadcrumbs: [Breadcrumb]?
    public init(level: SentryLevel = .error) { self.level = level }
}

public struct SentryId: CustomStringConvertible {
    public let description = "fake-event-id"
}

public final class Options {
    public var dsn: String?
    public var releaseName: String?
    public var dist: String?
    public var environment: String = "production"
    // Deliberately unsafe defaults prove production explicitly sets these.
    public var debug = true
    public var sendDefaultPii = true
    public var tracesSampleRate: NSNumber? = 1
    public var enableCrashHandler = false
    public var enableUncaughtNSExceptionReporting = false
    public var enableAutoSessionTracking = false
    public var enableAutoPerformanceTracing = true
    public var enableCoreDataTracing = true
    public var enableNetworkTracking = true
    public var enableNetworkBreadcrumbs = true
    public var enableCaptureFailedRequests = true
    public var enableAutoBreadcrumbTracking = true
    public var attachStacktrace = true
    public var enableAppHangTracking = true
    public var enableFileIOTracing = true
    public var enableMetricKit = true
    public var enableLogs = true
    public var beforeSend: ((Event) -> Event?)?
    public var beforeBreadcrumb: ((Breadcrumb) -> Breadcrumb?)?
    public init() {}
}

public enum SentrySDK {
    public private(set) static var startCount = 0
    public private(set) static var closeCount = 0
    public private(set) static var isActive = false
    public private(set) static var lastOptions: Options?
    public private(set) static var capturedEvents: [Event] = []
    public private(set) static var breadcrumbs: [Breadcrumb] = []
    public private(set) static var flushCount = 0

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

    /// Mirrors the SDK: inactive capture is a no-op, and beforeSend can drop.
    @discardableResult
    public static func capture(event: Event) -> SentryId {
        guard isActive, let options = lastOptions else { return SentryId() }
        if let processed = options.beforeSend.map({ $0(event) }) ?? event {
            capturedEvents.append(processed)
        }
        return SentryId()
    }

    public static func addBreadcrumb(_ crumb: Breadcrumb) {
        guard isActive, let options = lastOptions else { return }
        if let kept = options.beforeBreadcrumb.map({ $0(crumb) }) ?? crumb {
            breadcrumbs.append(kept)
        }
    }

    public static func flush(timeout: TimeInterval) {
        flushCount += 1
    }

    public static func reset() {
        startCount = 0
        closeCount = 0
        isActive = false
        lastOptions = nil
        capturedEvents = []
        breadcrumbs = []
        flushCount = 0
    }
}
