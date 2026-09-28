import Foundation

/// A one-use presentation hint shared by the sandboxed widget and the app.
/// It never authorizes protection or changes the user's saved preferences.
enum ControlCenterLaunchHandoff {
    static let key = "ControlCenterPendingLaunch"
    static let lifetime: TimeInterval = 60

    @discardableResult
    static func begin(in defaults: UserDefaults, now: Date = Date()) -> UUID {
        let token = UUID()
        defaults.set(["token": token.uuidString, "createdAt": now], forKey: key)
        return token
    }

    /// A failed launch may clean up only its own request, never a newer one.
    static func cancel(_ token: UUID, in defaults: UserDefaults) {
        guard defaults.dictionary(forKey: key)?["token"] as? String == token.uuidString else { return }
        defaults.removeObject(forKey: key)
    }

    /// Consume before the app decides whether to open its Settings window.
    /// Expiry also clears abandoned requests after a failed or crashed launch.
    static func consume(in defaults: UserDefaults, now: Date = Date()) -> Bool {
        let marker = defaults.dictionary(forKey: key)
        defaults.removeObject(forKey: key)
        guard let token = marker?["token"] as? String, UUID(uuidString: token) != nil,
              let createdAt = marker?["createdAt"] as? Date else { return false }
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age <= lifetime
    }
}
