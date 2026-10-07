//
//  DashboardViewModel.swift
//  PingWarden
//
//  State container for DashboardSettingsContent. Consumes shared ping-history
//  snapshots and owns the timeline event log, intervention counter, and target
//  selection logic, including auto-selection via TCPProbe.
//

import Foundation
import Network
import SwiftUI

@MainActor
class DashboardViewModel: ObservableObject {
    private(set) var stats = NetworkStatistics(
        currentPing: 0,
        averagePing: 0,
        minimumPing: 0,
        maximumPing: 0,
        jitter: 0,
        packetLoss: 0,
        quality: .poor
    )

    private(set) var pingHistory: [PingMonitor.PingResult] = []
    /// One publication per completed probe, after statistics, history, and
    /// the timeline have all been updated. This avoids several broad SwiftUI
    /// invalidation passes for the same network sample. The chart publishes
    /// separately, through `chart`, and less often.
    @Published private(set) var telemetryRevision: UInt64 = 0
    /// Every recorded event. Not published: appending one while the window
    /// is hidden must not redraw anything; the next revision carries it.
    private(set) var timelineEvents: [LatencyTimelineEvent] = []
    /// Events inside the selected timeframe, computed once per update
    /// instead of on every read during a redraw.
    private(set) var filteredTimelineEvents: [LatencyTimelineEvent] = []
    @Published private(set) var interventionCount: Int = 0
    @Published private(set) var baselineLatencyResults: [String: Double] = [:]
    @Published private(set) var isAutoSelectingTarget: Bool = false
    @Published private(set) var autoSelectionError: String?
    @Published var selectedTimeframe: Int = 15 { // minutes
        didSet {
            if !DashboardConfig.timeframeOptions.contains(selectedTimeframe) {
                selectedTimeframe = 15
                return
            }
            refreshPresentation(forceChart: true)
        }
    }
    @Published private(set) var targets: [PingTarget] = []
    @Published var selectedTargetID: String = "" {
        didSet {
            guard selectedTargetID != oldValue else { return }
            autoSelectionError = nil
            if !isApplyingProgrammaticSelection {
                // An explicit user selection supersedes a saved target that
                // is still waiting for its async source (gateway/GFN zones).
                pendingSavedTargetID = nil
            }
            // Never overwrite the persisted selection with a temporary
            // fallback while the saved target is still pending — otherwise a
            // saved GFN zone (or gateway) never survives a relaunch.
            if pendingSavedTargetID == nil {
                userDefaults.set(selectedTargetID, forKey: DashboardConfig.selectedTargetKey)
            }
            restartMonitoring()

            if selectedTarget?.source == .geforceNow {
                refreshGeForceNOWTargets(force: false)
            }
        }
    }
    @Published var updateInterval: TimeInterval = DashboardConfig.defaultInterval {
        didSet {
            let sanitized = sanitizedInterval(updateInterval)
            if sanitized != updateInterval {
                updateInterval = sanitized
                return
            }
            guard updateInterval != oldValue else { return }
            userDefaults.set(updateInterval, forKey: DashboardConfig.updateIntervalKey)
            restartMonitoring()
        }
    }
    @Published private(set) var isRefreshingGFNServers: Bool = false
    @Published private(set) var gfnRefreshError: String?
    @Published private(set) var customTargets: [CustomPingTarget] = []

    /// `nil` means the current target has not returned its first probe yet.
    /// Keeping failure distinct from a numeric zero lets the dashboard say
    /// "Measuring" or "Target Unreachable" instead of presenting 0 ms as a
    /// real latency measurement.
    private(set) var latestProbeSucceeded: Bool?
    private(set) var hasSuccessfulProbe = false

    /// Chart data, published at about one bucket's width rather than once
    /// per sample. See `refreshChartIfDue(force:)`.
    let chart = PingChartModel(timeframeMinutes: 15)

    private let pingMonitor = PingMonitor.shared
    private let telemetryConsumerID = UUID()
    private var telemetryObserverToken: UUID?
    nonisolated(unsafe) private var interventionSubscription: UUID?
    /// Whether this instance drives the shared probe. The Targets pane
    /// shows no live telemetry, so it starts without it.
    private var includesTelemetry = true
    /// Skips redraw work while the Dashboard window cannot be seen.
    private var visibilityGate = DeferredRefreshGate()
    private var lastChartRefresh: Date?
    /// The undo manager that holds removal actions targeting this model.
    /// Undo keeps an unowned reference to its target, so the actions are
    /// cleared before this model goes away.
    private weak var removalUndoManager: UndoManager?
    private var gfnRefreshTask: Task<Void, Never>?
    private var baselineSelectionTask: Task<Void, Never>?
    private var isStarted = false
    private var gfnTargets: [PingTarget] = []
    private var lastGFNRefreshDate: Date = .distantPast
    private var previousInterventionCount: Int = 0
    private var hasInitializedInterventionBaseline = false
    /// Saved target id from a previous session whose source (local gateway,
    /// GFN zone list) hasn't been resolved yet this session. Re-applied the
    /// moment the async source delivers it.
    private var pendingSavedTargetID: String?
    private var isApplyingProgrammaticSelection = false

    private let userDefaults = UserDefaults.standard
    private let customTargetStore = CustomPingTargetStore(userDefaults: PingWardenPreferences.shared.defaults)

    var selectedTarget: PingTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    /// Recomputes what the cards draw and publishes one revision. The
    /// chart rebuilds only when due, or when `forceChart` says its inputs
    /// changed shape (a new timeframe or target, or a return to view).
    private func refreshPresentation(forceChart: Bool) {
        refreshFilteredTimeline()
        refreshChartIfDue(force: forceChart)
        telemetryRevision &+= 1
    }

    private func refreshFilteredTimeline() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(selectedTimeframe * 60))
        filteredTimelineEvents = timelineEvents.filter { $0.timestamp > cutoff }
    }

    /// Rebuilding the chart for every sample cost about 23 ms at an hour of
    /// history, and each bucket only changes as it fills, so the chart
    /// refreshes at about one bucket's width: every sample for short
    /// timeframes, every ten seconds for an hour. The stat cards above it
    /// still update with every sample.
    private func refreshChartIfDue(force: Bool) {
        let now = Date()
        let bucket = ChartDownsampling.bucketSeconds(forTimeframeMinutes: selectedTimeframe)
        guard force || ChartDownsampling.isRefreshDue(now: now, lastRefresh: lastChartRefresh, bucketSeconds: bucket) else {
            return
        }
        lastChartRefresh = now
        chart.update(PingChartSnapshot.make(
            history: pingHistory,
            events: timelineEvents,
            timeframeMinutes: selectedTimeframe,
            now: now
        ))
    }

    /// Tells the model whether its window can be seen. Samples keep
    /// arriving while hidden so history and session recaps stay complete;
    /// only the redraw is skipped, and it catches up once on return.
    func setPresentationVisible(_ visible: Bool) {
        if visibilityGate.setVisible(visible) {
            refreshPresentation(forceChart: true)
        }
    }

    init() {
        // Initialize with base targets (no local gateway yet — resolved async in start())
        customTargets = customTargetStore.load()
        // Seed the GeForce NOW zones from the last successful discovery so a
        // saved GFN target matches right away. Without this every reopen of
        // the pane fell back to another target and probed it until the
        // network fetch below finished. The fetch still runs (subject to
        // the cooldown) and replaces the list when it succeeds.
        if let cached = GeForceNOWDiscovery.cachedTargets() {
            gfnTargets = cached.targets
            lastGFNRefreshDate = cached.fetchedAt
        }
        targets = Self.dedupe(
            Self.baseTargets(localGateway: nil)
                + gfnTargets.sorted { $0.displayName < $1.displayName }
                + Self.toPingTargets(customTargets)
        )

        if let savedInterval = userDefaults.object(forKey: DashboardConfig.updateIntervalKey) as? Double {
            updateInterval = sanitizedInterval(savedInterval)
        }

        let savedTargetID = normalizedSavedTargetID(userDefaults.string(forKey: DashboardConfig.selectedTargetKey))
        if let savedTargetID, targets.contains(where: { $0.id == savedTargetID }) {
            selectedTargetID = savedTargetID
        } else {
            // The saved target may belong to an async source (gateway, GFN
            // zone). Keep it pending and fall back for now; property
            // observers don't fire during init, so the persisted key is
            // not clobbered by the fallback.
            pendingSavedTargetID = savedTargetID
            selectedTargetID = targets.first?.id ?? ""
        }
    }

    // MARK: - Custom Targets

    /// Validate + persist a new custom target. Returns the validation error
    /// (if any) without mutating the store on failure.
    @discardableResult
    func addCustomTarget(displayName: String, host: String, port: Int) -> CustomPingTargetValidationError? {
        if let failure = CustomPingTargetStore.validate(displayName: displayName, host: host, port: port) {
            return failure
        }
        let target = CustomPingTarget(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: UInt16(port)
        )
        customTargets = customTargetStore.add(target)
        rebuildTargets()
        return nil
    }

    /// Removes a custom target and, when given an undo manager, registers
    /// Edit > Undo Remove Target so a mistaken click is recoverable without a
    /// confirmation dialog.
    func removeCustomTarget(id: UUID, undoManager: UndoManager? = nil) {
        guard let index = customTargets.firstIndex(where: { $0.id == id }) else { return }
        let removed = customTargets[index]
        let removedTargetID = Self.toPingTargets([removed]).first?.id
        let wasSelected = removedTargetID == selectedTargetID
        customTargets = customTargetStore.remove(id: id)
        rebuildTargets()

        guard let undoManager else { return }
        removalUndoManager = undoManager
        undoManager.registerUndo(withTarget: self) { model in
            model.restoreCustomTarget(removed, at: index, reselect: wasSelected, undoManager: undoManager)
        }
        undoManager.setActionName("Remove Target")
    }

    /// Undo for `removeCustomTarget`: puts the target back where it was and
    /// reselects it if it was selected, then registers the redo.
    private func restoreCustomTarget(
        _ target: CustomPingTarget,
        at index: Int,
        reselect: Bool,
        undoManager: UndoManager
    ) {
        customTargets = customTargetStore.insert(target, at: index)
        rebuildTargets()
        if reselect, let id = Self.toPingTargets([target]).first?.id, targets.contains(where: { $0.id == id }) {
            selectedTargetID = id
        }
        undoManager.registerUndo(withTarget: self) { model in
            model.removeCustomTarget(id: target.id, undoManager: undoManager)
        }
        undoManager.setActionName("Remove Target")
    }

    private static func toPingTargets(_ customs: [CustomPingTarget]) -> [PingTarget] {
        customs.map { custom in
            PingTarget(
                displayName: custom.displayName,
                host: custom.host,
                port: custom.port,
                source: .custom
            )
        }
    }

    /// Starts the model. `includesTelemetry: false` is for the Targets pane,
    /// which edits targets but shows no live latency, so it neither drives
    /// the shared probe nor polls the helper.
    func start(includesTelemetry: Bool = true) {
        guard !isStarted else { return }
        isStarted = true
        self.includesTelemetry = includesTelemetry

        // Resolve the local gateway off the main thread; the cache runs
        // /usr/sbin/route only after the network path changes.
        Task.detached(priority: .utility) {
            let gateway = GatewayAddressCache.shared.address()
            guard let gateway else { return }
            await MainActor.run { [weak self] in
                guard let self, self.isStarted else { return }
                self.rebuildTargets(localGateway: gateway)
            }
        }

        // Populate GeForce NOW zones up front so they're already in the picker
        // when the user opens it. (Previously a Picker .onTapGesture tried to
        // do this on open, but Pickers swallow the tap so it rarely fired.)
        refreshGeForceNOWTargets(force: false)

        guard includesTelemetry else { return }

        // One shared monitor feeds both the dashboard and menu metrics. The
        // callback arrives on main with statistics already computed off-main.
        telemetryObserverToken = pingMonitor.addObserver { [weak self] snapshot in
            Task { @MainActor in
                self?.handleTelemetrySnapshot(snapshot)
            }
        }

        startMonitoring(clearHistory: false)
        refreshPresentation(forceChart: true)

        interventionSubscription = InterventionCountFeed.shared.subscribe { [weak self] count in
            self?.handleInterventionCount(count)
        }
    }

    func stop() {
        isStarted = false
        if let telemetryObserverToken {
            pingMonitor.removeObserver(telemetryObserverToken)
            self.telemetryObserverToken = nil
        }
        pingMonitor.stop(consumerID: telemetryConsumerID)
        if let interventionSubscription {
            InterventionCountFeed.shared.unsubscribe(interventionSubscription)
            self.interventionSubscription = nil
        }
        removalUndoManager?.removeAllActions(withTarget: self)
        removalUndoManager = nil
        visibilityGate.reset()
        lastChartRefresh = nil
        gfnRefreshTask?.cancel()
        gfnRefreshTask = nil
        baselineSelectionTask?.cancel()
        baselineSelectionTask = nil
        isRefreshingGFNServers = false
        isAutoSelectingTarget = false
        // Re-baseline the intervention counter on the next start; otherwise
        // interventions that happened while the dashboard was hidden get
        // logged as one bogus timeline event timestamped at reopen.
        hasInitializedInterventionBaseline = false
    }

    deinit {
        // Backstop in case onDisappear -> stop() is ever skipped. Task
        // cancellation is safe off the main actor; the feed is main-actor
        // state, so its unsubscribe hops there. @StateObject deallocation
        // happens on the main thread in practice.
        if let interventionSubscription {
            Task { @MainActor in
                InterventionCountFeed.shared.unsubscribe(interventionSubscription)
            }
        }
        // Undo actions targeting this model are cleared in stop(), which
        // onDisappear always runs; UndoManager is main-actor API and cannot
        // be called from here.
        gfnRefreshTask?.cancel()
        baselineSelectionTask?.cancel()
        if let telemetryObserverToken {
            pingMonitor.removeObserver(telemetryObserverToken)
        }
        pingMonitor.stop(consumerID: telemetryConsumerID)
    }

    private func restartMonitoring() {
        guard isStarted, includesTelemetry else { return }
        startMonitoring(clearHistory: true)
    }

    private func startMonitoring(clearHistory: Bool) {
        guard let target = selectedTarget else { return }

        pingMonitor.start(
            consumerID: telemetryConsumerID,
            server: target.host,
            port: target.port,
            interval: updateInterval,
            priority: 100,
            resetHistory: clearHistory
        )
        if clearHistory {
            pingHistory.removeAll()
            latestProbeSucceeded = nil
            hasSuccessfulProbe = false
            if visibilityGate.noteChange() {
                refreshPresentation(forceChart: true)
            }
        }
    }

    private func handleTelemetrySnapshot(_ snapshot: PingMonitor.Snapshot) {
        stats = snapshot.statistics
        pingHistory = snapshot.history
        latestProbeSucceeded = snapshot.latestResult.success
        hasSuccessfulProbe = snapshot.latestResult.success || snapshot.history.contains(where: \.success)

        let result = snapshot.latestResult
        if result.success {
            let spikeThreshold = max(100.0, stats.averagePing * 2.0)
            if result.latencyMs >= spikeThreshold {
                appendTimelineEvent(.init(timestamp: result.timestamp, kind: .latencySpike(latencyMs: result.latencyMs)))
            }
        }

        if visibilityGate.noteChange() {
            refreshPresentation(forceChart: false)
        }
    }

    private func handleInterventionCount(_ count: Int) {
        if !hasInitializedInterventionBaseline {
            previousInterventionCount = count
            hasInitializedInterventionBaseline = true
            if interventionCount != count {
                interventionCount = count
            }
            return
        }

        guard count != previousInterventionCount else { return }
        if count > previousInterventionCount {
            let delta = count - previousInterventionCount
            appendTimelineEvent(.init(timestamp: Date(), kind: .awdlIntervention(delta: delta)))
            if visibilityGate.noteChange() {
                refreshFilteredTimeline()
            }
        }
        previousInterventionCount = count
        interventionCount = count
    }

    func refreshGeForceNOWTargetsOnDemand() {
        refreshGeForceNOWTargets(force: true)
    }

    func autoSelectNearestEndpoint() {
        guard !targets.isEmpty else { return }

        baselineSelectionTask?.cancel()
        isAutoSelectingTarget = true
        autoSelectionError = nil

        let candidates = targets
        baselineSelectionTask = Task { [weak self] in
            let sampleCount = DashboardConfig.baselineSampleCount
            let measurements = await Self.collectBaselineMeasurements(
                candidates: candidates,
                sampleCount: sampleCount
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }

                self.isAutoSelectingTarget = false
                self.baselineLatencyResults = measurements.mapValues(Self.robustAverage(from:))

                guard let best = self.baselineLatencyResults.min(by: { $0.value < $1.value }),
                      self.targets.contains(where: { $0.id == best.key }) else {
                    self.autoSelectionError = "No targets responded. Check your connection and try again."
                    return
                }

                self.selectedTargetID = best.key
            }
        }
    }

    private func refreshGeForceNOWTargets(force: Bool) {
        if !force,
           Date().timeIntervalSince(lastGFNRefreshDate) < DashboardConfig.gfnRefreshCooldownSeconds {
            return
        }

        gfnRefreshTask?.cancel()
        isRefreshingGFNServers = true
        gfnRefreshError = nil
        lastGFNRefreshDate = Date()

        gfnRefreshTask = Task { [weak self] in
            let discoveredTargets = await GeForceNOWDiscovery.fetchTargets()

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.isRefreshingGFNServers = false
                // nil = fetch failed. Keep whatever zones we already have —
                // wiping them would reset the user's selected GFN target and
                // clear their chart history over a transient network blip —
                // but tell the user, since a stale zone list can silently
                // cost real latency.
                guard let discoveredTargets else {
                    self.gfnRefreshError = "Could not refresh GeForce NOW zones. The list may be out of date."
                    return
                }
                self.gfnTargets = discoveredTargets
                self.rebuildTargets()
            }
        }
    }

    /// Rebuild the full target list from all sources. Pass `localGateway`
    /// when a freshly resolved gateway is in hand; otherwise the gateway
    /// cached in the existing targets is reused — do NOT call
    /// NetworkGatewayResolver here since this runs on @MainActor and the
    /// resolver spawns a blocking Process.
    private func rebuildTargets(localGateway: String? = nil) {
        let gatewayHost = localGateway ?? targets.first(where: { $0.source == .local })?.host
        let baseTargets = Self.baseTargets(localGateway: gatewayHost)
        let sortedGFNTargets = gfnTargets.sorted { $0.displayName < $1.displayName }
        let customAsTargets = Self.toPingTargets(customTargets)

        targets = Self.dedupe(baseTargets + sortedGFNTargets + customAsTargets)
        reapplySelectionAfterTargetsChanged(previousSelection: selectedTargetID)
    }

    /// Duplicate host:port combinations (e.g. a custom target that shadows a
    /// built-in) would produce duplicate SwiftUI identifiers in the picker;
    /// the first occurrence wins.
    private static func dedupe(_ list: [PingTarget]) -> [PingTarget] {
        var deduplicated: [PingTarget] = []
        var seenIDs = Set<String>()
        for target in list where seenIDs.insert(target.id).inserted {
            deduplicated.append(target)
        }
        return deduplicated
    }

    /// Re-resolve the selection after the target list changed: a saved-but-
    /// pending target wins the moment its source delivers it, then the
    /// previous selection if still present, then the local-gateway/first
    /// fallback.
    private func reapplySelectionAfterTargetsChanged(previousSelection: String) {
        if let pending = pendingSavedTargetID, targets.contains(where: { $0.id == pending }) {
            pendingSavedTargetID = nil
            applyProgrammaticSelection(pending)
            return
        }
        if targets.contains(where: { $0.id == previousSelection }) {
            if selectedTargetID != previousSelection {
                applyProgrammaticSelection(previousSelection)
            }
            return
        }
        applyProgrammaticSelection(
            targets.first(where: { $0.source == .local })?.id ?? targets.first?.id ?? ""
        )
    }

    /// Selection changes made by the model itself (fallbacks, restoring a
    /// pending saved target) must not discard the pending saved target the
    /// way an explicit user pick does.
    private func applyProgrammaticSelection(_ id: String) {
        isApplyingProgrammaticSelection = true
        selectedTargetID = id
        isApplyingProgrammaticSelection = false
    }

    private static func baseTargets(localGateway: String?) -> [PingTarget] {
        var targets: [PingTarget] = []

        if let localGateway, !localGateway.isEmpty {
            targets.append(PingTarget(
                displayName: "Local Gateway (\(localGateway))",
                host: localGateway,
                port: 53,
                source: .local
            ))
        }

        targets.append(PingTarget(
            displayName: "Cloudflare DNS (Global)",
            host: "1.1.1.1",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Cloudflare DNS Secondary (Global)",
            host: "1.0.0.1",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Google DNS (Global)",
            host: "8.8.8.8",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Google DNS Secondary (Global)",
            host: "8.8.4.4",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Quad9 DNS (Global)",
            host: "9.9.9.9",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Quad9 DNS Secondary (Global)",
            host: "149.112.112.112",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "OpenDNS (Global)",
            host: "208.67.222.222",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "OpenDNS Secondary (Global)",
            host: "208.67.220.220",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "AdGuard DNS (Global)",
            host: "94.140.14.14",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "AdGuard DNS Secondary (Global)",
            host: "94.140.15.15",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "CleanBrowsing DNS (Global)",
            host: "185.228.168.9",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "CleanBrowsing DNS Secondary (Global)",
            host: "185.228.169.9",
            port: 53,
            source: .publicDNS
        ))

        targets.append(PingTarget(
            displayName: "Valve Steam API",
            host: "api.steampowered.com",
            port: 443,
            source: .gaming
        ))

        targets.append(PingTarget(
            displayName: "Battle.net API",
            host: "us.api.blizzard.com",
            port: 443,
            source: .gaming
        ))

        targets.append(PingTarget(
            displayName: "GeForce NOW Routing API",
            host: "prod.cloudmatchbeta.nvidiagrid.net",
            port: 443,
            source: .geforceNow
        ))

        return targets
    }

    private func appendTimelineEvent(_ event: LatencyTimelineEvent) {
        if let last = timelineEvents.last,
           abs(last.timestamp.timeIntervalSince(event.timestamp)) < 2,
           last.label == event.label {
            return
        }

        timelineEvents.append(event)

        let cutoff = Date().addingTimeInterval(-DashboardConfig.historyRetentionSeconds)
        timelineEvents.removeAll { $0.timestamp < cutoff }
    }

    private func sanitizedInterval(_ rawInterval: TimeInterval) -> TimeInterval {
        guard rawInterval > 0 else {
            return DashboardConfig.defaultInterval
        }

        if DashboardConfig.intervalOptions.contains(rawInterval) {
            return rawInterval
        }

        return DashboardConfig.intervalOptions.min { abs($0 - rawInterval) < abs($1 - rawInterval) } ?? DashboardConfig.defaultInterval
    }

    private func normalizedSavedTargetID(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return nil
        }

        if rawValue.contains(":") {
            return rawValue
        }

        switch rawValue {
        case "8.8.8.8":
            return "8.8.8.8:53"
        case "1.1.1.1":
            return "1.1.1.1:53"
        default:
            let defaultPort: UInt16 = rawValue.contains("nvidia") ? 443 : 53
            return "\(rawValue):\(defaultPort)"
        }
    }

    /// Dedicated queue for the blocking baseline probes. Running them
    /// directly inside task-group children would block Swift-concurrency
    /// cooperative-pool threads for seconds (timeout × samples × targets),
    /// starving every other async task in the app.
    nonisolated private static let baselineProbeQueue = DispatchQueue(
        label: "com.amesvt.pingwarden.baselineprobe",
        qos: .utility,
        attributes: .concurrent
    )

    nonisolated private static func measureLatencyOffPool(
        host: String,
        port: UInt16,
        timeoutSeconds: Int
    ) async -> Double? {
        let cancellationToken = TCPProbe.CancellationToken()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                baselineProbeQueue.async {
                    continuation.resume(returning: TCPProbe.measureLatency(
                        host: host,
                        port: port,
                        timeoutSeconds: timeoutSeconds,
                        cancellationToken: cancellationToken
                    ))
                }
            }
        } onCancel: {
            cancellationToken.cancel()
        }
    }

    nonisolated private static func collectBaselineMeasurements(
        candidates: [PingTarget],
        sampleCount: Int
    ) async -> [String: [Double]] {
        // Bound the fan-out: each candidate parks a blocking probe on
        // baselineProbeQueue, and an unbounded group over ~36 targets would
        // drive GCD to spawn dozens of overcommit threads in one burst.
        let maxConcurrentProbes = 8

        return await withTaskGroup(of: (String, [Double])?.self) { group in
            func addProbeTask(for target: PingTarget) {
                group.addTask {
                    var samples: [Double] = []
                    for sampleIndex in 0..<sampleCount {
                        if Task.isCancelled {
                            return nil
                        }

                        if let latency = await measureLatencyOffPool(
                            host: target.host,
                            port: target.port,
                            timeoutSeconds: DashboardConfig.baselineProbeTimeoutSeconds
                        ) {
                            samples.append(latency)
                        }

                        if sampleIndex < sampleCount - 1 {
                            try? await Task.sleep(nanoseconds: DashboardConfig.baselineSampleSpacingNanoseconds)
                        }
                    }

                    guard !samples.isEmpty else { return nil }
                    return (target.id, samples)
                }
            }

            var nextCandidateIndex = 0
            while nextCandidateIndex < candidates.count && nextCandidateIndex < maxConcurrentProbes {
                addProbeTask(for: candidates[nextCandidateIndex])
                nextCandidateIndex += 1
            }

            var measurements: [String: [Double]] = [:]
            for await result in group {
                if nextCandidateIndex < candidates.count {
                    addProbeTask(for: candidates[nextCandidateIndex])
                    nextCandidateIndex += 1
                }
                guard let (targetID, samples) = result else { continue }
                measurements[targetID] = samples
            }
            return measurements
        }
    }

    nonisolated private static func robustAverage(from values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count < 3 {
            return sorted.reduce(0, +) / Double(sorted.count)
        }

        // Drop one high and one low sample to reduce transient spikes.
        let trimmed = sorted.dropFirst().dropLast()
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }
}

// MARK: - Chart data

/// Everything the Dashboard chart draws, built in one pass so the chart's
/// body only reads stored values.
struct PingChartSnapshot {
    /// One uninterrupted run of successful probes. Swift Charts connects
    /// every mark in a series, so each run is its own series and a failed
    /// probe leaves an honest gap. The id is the run's first timestamp,
    /// which stays the same while that run is on screen.
    struct Segment: Identifiable {
        let id: Date
        let points: [PingMonitor.PingResult]
    }

    /// Totals over the raw samples in the window, not the thinned chart
    /// points, so VoiceOver reports true sample counts.
    struct Summary: Equatable {
        var probeCount = 0
        var successCount = 0
        var currentMs = 0.0
        var averageMs = 0.0
        var peakMs = 0.0
        var eventCount = 0
    }

    static let spikeThresholdMs = 100.0

    var timeframeMinutes: Int
    var windowStart: Date
    var windowEnd: Date
    var tickDates: [Date] = []
    var segments: [Segment] = []
    var spikePoints: [PingMonitor.PingResult] = []
    var failedPoints: [PingMonitor.PingResult] = []
    var latestPoint: PingMonitor.PingResult?
    /// Bucketed probes, successes and failures, for the VoiceOver chart
    /// descriptor.
    var probePoints: [PingMonitor.PingResult] = []
    /// Timeline events thinned to one rule per kind per few buckets.
    var events: [LatencyTimelineEvent] = []
    var yUpperBound = 125.0
    var summary = Summary()
    var hasAnyHistory = false

    var isEmpty: Bool { probePoints.isEmpty }

    static func make(
        history: [PingMonitor.PingResult],
        events: [LatencyTimelineEvent],
        timeframeMinutes: Int,
        now: Date
    ) -> PingChartSnapshot {
        let windowStart = now.addingTimeInterval(-TimeInterval(timeframeMinutes * 60))
        var snapshot = PingChartSnapshot(timeframeMinutes: timeframeMinutes, windowStart: windowStart, windowEnd: now)
        snapshot.hasAnyHistory = !history.isEmpty
        snapshot.tickDates = ChartTimeAxis.tickDates(
            windowStart: windowStart,
            windowEnd: now,
            timeframeMinutes: timeframeMinutes
        )

        // History is appended in time order, so the window starts at a
        // binary-searched index instead of a filter over every sample.
        let start = ChartDownsampling.firstIndex(in: history, after: windowStart, timestamp: \.timestamp)
        let window = history[start...]

        var successCount = 0
        var total = 0.0
        var peak = 0.0
        var current: Double?
        for probe in window where probe.success {
            successCount += 1
            total += probe.latencyMs
            peak = max(peak, probe.latencyMs)
            current = probe.latencyMs
        }
        let windowEvents = events.filter { $0.timestamp > windowStart }
        snapshot.summary = Summary(
            probeCount: window.count,
            successCount: successCount,
            currentMs: current ?? 0,
            averageMs: successCount > 0 ? total / Double(successCount) : 0,
            peakMs: peak,
            eventCount: windowEvents.count
        )

        let bucket = ChartDownsampling.bucketSeconds(forTimeframeMinutes: timeframeMinutes)
        let points = ChartDownsampling.bucketed(
            window,
            bucketSeconds: bucket,
            timestamp: \.timestamp,
            latencyMs: \.latencyMs,
            success: \.success
        )
        snapshot.probePoints = points

        var segments: [Segment] = []
        var run: [PingMonitor.PingResult] = []
        for point in points {
            if point.success {
                run.append(point)
            } else if let first = run.first {
                segments.append(Segment(id: first.timestamp, points: run))
                run = []
            }
        }
        if let first = run.first {
            segments.append(Segment(id: first.timestamp, points: run))
        }
        snapshot.segments = segments
        snapshot.spikePoints = points.filter { $0.success && $0.latencyMs >= spikeThresholdMs }
        snapshot.failedPoints = points.filter { !$0.success }
        snapshot.latestPoint = points.last.flatMap { $0.success ? $0 : nil }
        snapshot.events = ChartDownsampling.mergedEvents(
            windowEvents,
            minimumSpacing: bucket * 4,
            timestamp: \.timestamp,
            kind: { event -> Int in
                if case .latencySpike = event.kind { return 0 }
                return 1
            }
        )

        // Headroom above the tallest point, rounded to a 25 ms gridline.
        let padded = max(125, max(100, peak * 1.1) * 1.15)
        snapshot.yUpperBound = (padded / 25).rounded(.up) * 25
        return snapshot
    }
}

/// Publishes chart data on its own, so a new sample that does not change
/// the chart does not make Swift Charts diff every mark again.
@MainActor
final class PingChartModel: ObservableObject {
    @Published private(set) var snapshot: PingChartSnapshot

    init(timeframeMinutes: Int) {
        let now = Date()
        snapshot = PingChartSnapshot.make(history: [], events: [], timeframeMinutes: timeframeMinutes, now: now)
    }

    func update(_ snapshot: PingChartSnapshot) {
        self.snapshot = snapshot
    }
}

// MARK: - Gateway cache

/// The default gateway, cached until the network path changes. Each
/// Dashboard or Targets appearance used to launch /usr/sbin/route.
final class GatewayAddressCache: @unchecked Sendable {
    static let shared = GatewayAddressCache()

    private let lock = NSLock()
    private var cachedAddress: String?
    private var hasCachedAddress = false
    /// Bumped on every path change, so a lookup that raced a change is
    /// not stored as current.
    private var generation: UInt64 = 0
    private let pathMonitor = NWPathMonitor()

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            self?.invalidate()
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.amesvt.pingwarden.gatewaycache", qos: .utility))
    }

    /// Blocks while `route` runs on a cache miss, so call it off the main
    /// thread.
    func address() -> String? {
        lock.lock()
        if hasCachedAddress {
            let address = cachedAddress
            lock.unlock()
            return address
        }
        let lookupGeneration = generation
        lock.unlock()

        let address = NetworkGatewayResolver.defaultGatewayAddress()

        lock.lock()
        if generation == lookupGeneration {
            cachedAddress = address
            hasCachedAddress = true
        }
        lock.unlock()
        return address
    }

    private func invalidate() {
        lock.lock()
        generation &+= 1
        hasCachedAddress = false
        cachedAddress = nil
        lock.unlock()
    }
}
