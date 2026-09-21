import Foundation

/// Registration defaults never replace a user's persisted reporting choice.
enum CrashReportingPolicy {
    static let preferenceKey = "CrashReportingEnabled"

    static func registerDefault(in defaults: UserDefaults) {
        defaults.register(defaults: [preferenceKey: true])
    }

    static func prepareForRemoval(in defaults: UserDefaults) {
        // Clearing persistent preferences must not enable reporting again in
        // the departing process. The registration domain is not persisted.
        defaults.register(defaults: [preferenceKey: false])
    }
}
