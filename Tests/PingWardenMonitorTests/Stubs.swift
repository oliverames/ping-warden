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
    func getVersion(reply: @escaping (String) -> Void) { versions.append(reply) }
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
    var status: Status = .enabled
    static func daemon(plistName: String) -> SMAppService { SMAppService() }
    static func openSystemSettingsLoginItems() { fatalError("Must never open real system settings") }
    func register() throws { fatalError("Must never register a helper") }
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
