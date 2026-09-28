import Foundation

// Latency-session fixture. The real ProtectedSessionCoordinator is not
// compiled here because its store writes to Application Support and its
// probes use the network.
enum ProtectedSessionTrigger: String, Sendable { case manual, gameMode }
enum ProtectedSessionEndReason: String, Sendable {
    case endedByUser, protectionTurnedOff, protectionPaused, gameModeEnded, applicationTerminated, protectionFailed, unknown
}
@MainActor final class ProtectedSessionCoordinator {
    static let shared = ProtectedSessionCoordinator()
    var phase: ProtectionSessionPhase = .idle
    var activeTrigger: ProtectedSessionTrigger?
    var lastError: String?
    var interruptionsNoted = 0
    var endings: [(ProtectedSessionEndReason, Bool)] = []
    var isActive: Bool { phase == .active }
    var isTransitioning: Bool { phase == .starting || phase == .stopping }
    func start(trigger: ProtectedSessionTrigger) async { phase = .active; activeTrigger = trigger }
    func stop(endReason: ProtectedSessionEndReason, protectionWasInterrupted: Bool) async {
        if phase == .active { endings.append((endReason, protectionWasInterrupted)) }
        phase = .idle
        activeTrigger = nil
    }
    func noteProtectionInterrupted() { if phase == .active { interruptionsNoted += 1 } }
    func finishForTermination() { phase = .idle; activeTrigger = nil }
}
