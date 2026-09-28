import Foundation

// Platform boundaries for the coordinator harness. Everything here is
// in-memory: no service is registered, no helper is contacted, no alert or
// System Settings pane opens, and no real preference store is read or written.

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
    var statuses: [(String) -> Void] = []
    func setAWDLEnabled(_ enable: Bool, reply: @escaping (Bool) -> Void) { commands.append((enable, reply)) }
    func isAWDLEnabled(reply: @escaping (Bool) -> Void) { states.append(reply) }
    // When set, every version request answers at once, like a live daemon.
    static var autoReplyVersion: String?
    // When false, status requests wait, like a helper that never answers.
    static var answersStatus = true
    func getVersion(reply: @escaping (String) -> Void) {
        if let version = Self.autoReplyVersion { reply(version) } else { versions.append(reply) }
    }
    func getAWDLStatus(reply: @escaping (String) -> Void) {
        if Self.answersStatus { reply("fake") } else { statuses.append(reply) }
    }
    func getAWDLInterventionCount(reply: @escaping (Int) -> Void) { reply(0) }
    func resetAWDLInterventionCount(reply: @escaping (Bool) -> Void) { reply(true) }
}
final class NSXPCConnection {
    struct Options { static let privileged = Options() }
    static var instances: [NSXPCConnection] = []
    // A Mach service with no registered job invalidates at once.
    static var invalidateWhenUnregistered = false
    var remoteObjectInterface: NSXPCInterface?
    var interruptionHandler: (() -> Void)?
    var invalidationHandler: (() -> Void)?
    private let errorHandlers = LockedValue<[(Error) -> Void]>([])
    var didInvalidate = false
    let helper = FakeHelper()
    init(machServiceName: String, options: Options) { Self.instances.append(self) }
    func activate() {
        if Self.invalidateWhenUnregistered && SMAppService.fixtureStatus != .enabled {
            DispatchQueue.main.async { self.invalidate() }
        }
    }
    func invalidate() { guard !didInvalidate else { return }; didInvalidate = true; invalidationHandler?() }
    func remoteObjectProxyWithErrorHandler(_ callback: @escaping (Error) -> Void) -> Any {
        errorHandlers.withValue { $0.append(callback) }
        return helper
    }
    /// Deliver an XPC error to every proxy handed out, as the runtime does
    /// when a connection is refused or dropped with messages outstanding.
    func failProxies(code: Int) {
        let handlers = errorHandlers.withValue { handlers -> [(Error) -> Void] in
            defer { handlers = [] }
            return handlers
        }
        let error = NSError(domain: NSCocoaErrorDomain, code: code)
        handlers.forEach { $0(error) }
    }
}
final class NSXPCInterface { init(with type: Any.Type) {} }
final class SMAppService {
    enum Status { case enabled, notRegistered, notFound, requiresApproval }
    // One in-memory registration shared by every handle, like the system's.
    static var fixtureStatus: Status = .enabled
    // Registration calls reach only this fixture, and only in tests that opt in.
    static var fixtureAllowsRegistration = false
    static var registerCalls = 0
    static var unregisterCalls = 0
    static var statusAfterRegister: Status = .enabled
    static var onUnregister: (() -> Void)?
    // Counted, never performed.
    static var openSettingsCalls = 0
    var status: Status { Self.fixtureStatus }
    static func daemon(plistName: String) -> SMAppService { SMAppService() }
    static func openSystemSettingsLoginItems() { openSettingsCalls += 1 }
    func register() throws {
        precondition(Self.fixtureAllowsRegistration, "Must never register a helper")
        Self.registerCalls += 1
        Self.fixtureStatus = Self.statusAfterRegister
    }
    func unregister() async throws {
        precondition(Self.fixtureAllowsRegistration, "Must never unregister a helper")
        Self.unregisterCalls += 1
        Self.fixtureStatus = .notRegistered
        Self.onUnregister?()
    }
}
final class PingWardenPreferences: @unchecked Sendable {
    static let shared = PingWardenPreferences()
    var isMonitoringEnabled = false
    var effectiveMonitoringEnabled = false
    var lastKnownState = "unknown"
    var protectionPauseUntil: Date?
}
final class LicenseManager: @unchecked Sendable {
    static let shared = LicenseManager()
    static var launchGateAllowsProtection = true
    static let donationConversionEmail = "fixture@example.invalid"
    var canEnableProtection = true
    var grandfatherWindowExpired = false
}
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
/// Replaces `ifconfig awdl0` so no test depends on this Mac's radio.
enum HarnessInterface { static var flagsLine = "" }
