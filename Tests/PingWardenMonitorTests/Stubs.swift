import Foundation

protocol PingWardenHelperProtocol: AnyObject {
    func setAWDLEnabled(_ enable: Bool, reply: @escaping (Bool) -> Void)
    func isAWDLEnabled(reply: @escaping (Bool) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
    func getAWDLStatus(reply: @escaping (String) -> Void)
    func getAWDLInterventionCount(reply: @escaping (Int) -> Void)
    func resetAWDLInterventionCount(reply: @escaping (Bool) -> Void)
}
final class FakeHelper: PingWardenHelperProtocol {
    var commands: [(Bool, (Bool) -> Void)] = []
    var versions: [(String) -> Void] = []
    var states: [(Bool) -> Void] = []
    func setAWDLEnabled(_ enable: Bool, reply: @escaping (Bool) -> Void) { commands.append((enable, reply)) }
    func isAWDLEnabled(reply: @escaping (Bool) -> Void) { states.append(reply) }
    // When set, every version request answers at once, like a live daemon.
    static var autoReplyVersion: String?
    func getVersion(reply: @escaping (String) -> Void) {
        if let version = Self.autoReplyVersion { reply(version) } else { versions.append(reply) }
    }
    func getAWDLStatus(reply: @escaping (String) -> Void) { reply("fake") }
    func getAWDLInterventionCount(reply: @escaping (Int) -> Void) { reply(0) }
    func resetAWDLInterventionCount(reply: @escaping (Bool) -> Void) { reply(true) }
}
final class NSXPCConnection {
    struct Options { static let privileged = Options() }
    static var instances: [NSXPCConnection] = []
    var remoteObjectInterface: NSXPCInterface?
    var interruptionHandler: (() -> Void)?
    var invalidationHandler: (() -> Void)?
    var errorHandler: ((Error) -> Void)?
    var didInvalidate = false
    let helper = FakeHelper()
    init(machServiceName: String, options: Options) { Self.instances.append(self) }
    func activate() {}
    func invalidate() { guard !didInvalidate else { return }; didInvalidate = true; invalidationHandler?() }
    func remoteObjectProxyWithErrorHandler(_ callback: @escaping (Error) -> Void) -> Any { errorHandler = callback; return helper }
}
final class NSXPCInterface { init(with type: Any.Type) {} }
final class SMAppService {
    enum Status { case enabled, notRegistered, notFound, requiresApproval }
    // One in-memory registration shared by every handle, like the system's.
    static var fixtureStatus: Status = .enabled
    // Registration calls reach only this fixture, and only in tests that opt in.
    static var fixtureAllowsRegistration = false
    static var fixtureRegistrationError: NSError?
    static var fixtureStatusAfterRegistration: Status = .enabled
    static var settingsOpenCalls = 0
    static var registerCalls = 0
    static var unregisterCalls = 0
    var status: Status { Self.fixtureStatus }
    static func daemon(plistName: String) -> SMAppService { SMAppService() }
    static func openSystemSettingsLoginItems() {
        precondition(Self.fixtureAllowsRegistration, "Settings handoff must be explicitly enabled in the fixture")
        Self.settingsOpenCalls += 1
    }
    func register() throws {
        precondition(Self.fixtureAllowsRegistration, "Must never register a helper")
        Self.registerCalls += 1
        Self.fixtureStatus = Self.fixtureStatusAfterRegistration
        if let error = Self.fixtureRegistrationError { throw error }
    }
    func unregister() async throws {
        precondition(Self.fixtureAllowsRegistration, "Must never unregister a helper")
        Self.unregisterCalls += 1
        Self.fixtureStatus = .notRegistered
    }
}
final class PingWardenPreferences {
    static let shared = PingWardenPreferences()
    var isMonitoringEnabled = false
    var effectiveMonitoringEnabled = false
    var lastKnownState = "unknown"
    var protectionPauseUntil: Date?
}
enum LicenseManager { static var launchGateAllowsProtection = true }
final class NSAlert {
    enum Style { case critical }
    static var messages: [String] = []
    var messageText = ""
    var informativeText = ""
    var alertStyle: Style = .critical
    func addButton(withTitle: String) {}
    func runModal() { Self.messages.append(informativeText) }
}
extension Notification.Name { static let awdlMonitorStateChanged = Notification.Name("HarnessAWDLChanged") }
// Only the notification name; the harness never posts app activation.
enum NSApplication { static let didBecomeActiveNotification = Notification.Name("HarnessAppDidBecomeActive") }
