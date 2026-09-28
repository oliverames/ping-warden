//
//  MonitoringStateStore.swift
//  PingWarden
//
//  Shared observer bridge for monitor runtime state and cross-process intent changes.
//

import Foundation

@MainActor
final class MonitoringStateStore: ObservableObject {
    @Published private(set) var isMonitoring = PingWardenMonitor.shared.isMonitoringActive
    @Published private(set) var isHelperRegistered = PingWardenMonitor.shared.isHelperRegistered
    @Published private(set) var interventionCount: Int = 0

    nonisolated(unsafe) private var monitoringIntentObserver: NSObjectProtocol?
    nonisolated(unsafe) private var monitoringEffectiveObserver: NSObjectProtocol?
    private var monitorStateObserverToken: UUID?
    nonisolated(unsafe) private var interventionSubscription: UUID?
    private var isObserving = false

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        monitoringIntentObserver = DistributedNotificationCenter.default().addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        monitoringEffectiveObserver = DistributedNotificationCenter.default().addObserver(
            forName: .awdlEffectiveMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        monitorStateObserverToken = PingWardenMonitor.shared.addStateObserver { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }

        interventionSubscription = InterventionCountFeed.shared.subscribe { [weak self] count in
            self?.applyInterventionCount(count)
        }

        refresh()
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false

        if let observer = monitoringIntentObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            monitoringIntentObserver = nil
        }

        if let observer = monitoringEffectiveObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            monitoringEffectiveObserver = nil
        }

        if let token = monitorStateObserverToken {
            PingWardenMonitor.shared.removeStateObserver(token)
            monitorStateObserverToken = nil
        }

        if let token = interventionSubscription {
            InterventionCountFeed.shared.unsubscribe(token)
            interventionSubscription = nil
        }
    }

    deinit {
        // Backstop in case onDisappear -> stopObserving() is ever skipped
        // (e.g. a future refactor that drops the callback). Observer removal
        // and registry-token removal are safe off the main actor; the feed
        // is main-actor state, so its unsubscribe hops there.
        if let observer = monitoringIntentObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = monitoringEffectiveObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let token = monitorStateObserverToken {
            PingWardenMonitor.shared.removeStateObserver(token)
        }
        if let token = interventionSubscription {
            Task { @MainActor in
                InterventionCountFeed.shared.unsubscribe(token)
            }
        }
    }

    func refresh() {
        let monitoring = PingWardenMonitor.shared.isMonitoringActive
        if monitoring != isMonitoring {
            isMonitoring = monitoring
        }
        let registered = PingWardenMonitor.shared.isHelperRegistered
        if registered != isHelperRegistered {
            isHelperRegistered = registered
        }
        if isMonitoring {
            InterventionCountFeed.shared.refreshNow()
        } else {
            applyInterventionCount(0)
        }
    }

    private func applyInterventionCount(_ count: Int) {
        // The count only means something while protection runs, and an
        // unchanged value must not republish the menu.
        let shown = isMonitoring ? count : 0
        if shown != interventionCount {
            interventionCount = shown
        }
    }
}

/// One poll of the helper's intervention counter, shared by every surface
/// that shows it. The Dashboard and the menu each ran their own 5-second
/// timer before, so both asked the helper the same question at once.
@MainActor
final class InterventionCountFeed {
    static let shared = InterventionCountFeed()

    static let pollInterval: TimeInterval = 5

    private var subscribers: [UUID: (Int) -> Void] = [:]
    private var timer: Timer?
    /// When the outstanding request started. An XPC error can drop the
    /// reply entirely, so a request older than two poll intervals no longer
    /// blocks the next one.
    private var requestStartedAt: Date?

    private init() {}

    /// Registers a handler for every count the helper reports, and asks for
    /// a fresh count right away. The handler runs on the main actor.
    func subscribe(_ handler: @escaping (Int) -> Void) -> UUID {
        let token = UUID()
        subscribers[token] = handler
        startTimerIfNeeded()
        refreshNow()
        return token
    }

    func unsubscribe(_ token: UUID) {
        subscribers.removeValue(forKey: token)
        guard subscribers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Asks the helper for its count now, unless a request is already
    /// under way; its answer reaches every subscriber.
    func refreshNow() {
        guard !subscribers.isEmpty else { return }
        if let started = requestStartedAt, Date().timeIntervalSince(started) < Self.pollInterval * 2 {
            return
        }
        // Without a registered helper there is nobody to ask, and each
        // attempt used to log a warning every five seconds.
        guard PingWardenMonitor.shared.isHelperRegistered else { return }
        requestStartedAt = Date()
        PingWardenMonitor.shared.getInterventionCount { [weak self] count in
            Task { @MainActor in
                guard let self else { return }
                self.requestStartedAt = nil
                guard let count else { return }
                for handler in self.subscribers.values {
                    handler(count)
                }
            }
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor in
                InterventionCountFeed.shared.refreshNow()
            }
        }
        // The count is informational, so let the system batch this wakeup.
        timer.tolerance = Self.pollInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
