//
//  MonitoringStateStore.swift
//  AWDLControl
//
//  Shared observer bridge for monitor runtime state and cross-process intent changes.
//

import Foundation

@MainActor
final class MonitoringStateStore: ObservableObject {
    @Published private(set) var isMonitoring = AWDLMonitor.shared.isMonitoringActive
    @Published private(set) var isHelperRegistered = AWDLMonitor.shared.isHelperRegistered
    @Published private(set) var interventionCount: Int = 0

    private var monitoringIntentObserver: NSObjectProtocol?
    private var monitoringEffectiveObserver: NSObjectProtocol?
    private var monitorStateObserverToken: UUID?
    private var interventionTimer: Timer?
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

        monitorStateObserverToken = AWDLMonitor.shared.addStateObserver { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }

        interventionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInterventionCount()
            }
        }

        refresh()
        refreshInterventionCount()
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
            AWDLMonitor.shared.removeStateObserver(token)
            monitorStateObserverToken = nil
        }

        interventionTimer?.invalidate()
        interventionTimer = nil
    }

    func refresh() {
        isMonitoring = AWDLMonitor.shared.isMonitoringActive
        isHelperRegistered = AWDLMonitor.shared.isHelperRegistered
        refreshInterventionCount()
    }

    private func refreshInterventionCount() {
        guard isMonitoring else {
            interventionCount = 0
            return
        }

        AWDLMonitor.shared.getInterventionCount { [weak self] count in
            guard let self else { return }
            Task { @MainActor in
                self.interventionCount = count
            }
        }
    }
}
