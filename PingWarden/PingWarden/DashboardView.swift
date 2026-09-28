//
//  DashboardView.swift
//  PingWarden
//
//  Network quality dashboard for cloud gaming.
//  Shows real-time ping, graphs, and AWDL intervention stats.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import SwiftUI
import Charts
import AppKit
import Accessibility

struct PingTarget: Identifiable, Hashable {
    enum Source: Int {
        case local
        case publicDNS
        case geforceNow
        case gaming
        case custom
    }

    let id: String
    let displayName: String
    let host: String
    let port: UInt16
    let source: Source

    init(displayName: String, host: String, port: UInt16, source: Source) {
        self.displayName = displayName
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.source = source
        self.id = "\(self.host.lowercased()):\(port)"
    }
}

struct LatencyTimelineEvent: Identifiable {
    enum Kind {
        case latencySpike(latencyMs: Double)
        case awdlIntervention(delta: Int)
    }

    let id = UUID()
    let timestamp: Date
    let kind: Kind

    var label: String {
        switch kind {
        case .latencySpike(let latency):
            return String(format: "Latency spike: %.0f ms", latency)
        case .awdlIntervention(let delta):
            if delta == 1 {
                return "Intervention attempt"
            }
            return "Intervention attempts (+\(delta))"
        }
    }

    var symbol: String {
        switch kind {
        case .latencySpike:
            return "exclamationmark.triangle.fill"
        case .awdlIntervention:
            return "arrow.counterclockwise"
        }
    }

    var color: Color {
        switch kind {
        case .latencySpike:
            return .orange
        case .awdlIntervention:
            return .green
        }
    }
}

enum DashboardConfig {
    static let intervalOptions: [TimeInterval] = [1, 2, 5, 10]
    static let timeframeOptions: [Int] = [1, 5, 15, 30, 60]
    static let defaultInterval: TimeInterval = 2
    static let gfnRefreshCooldownSeconds: TimeInterval = 15
    static let selectedTargetKey = "DashboardSelectedPingTargetID"
    static let updateIntervalKey = "DashboardUpdateInterval"
    static let historyRetentionSeconds: TimeInterval = 3900
    static let baselineSampleCount = 3
    static let baselineProbeTimeoutSeconds = 1
    static let baselineSampleSpacingNanoseconds: UInt64 = 100_000_000
}

private enum DashboardLayout {
    static let cardCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 12
}

private enum LatencyPalette {
    // Light variants are darker so they hit WCAG AA (>=4.5:1) against
    // .regularMaterial; dark variants keep the original vivid palette which
    // already met AA against dark material backgrounds. Verified with
    // python contrast calc, 2026-05-27. See PR for the table.
    static let excellent = adaptive(light: (0.00, 0.46, 0.12), dark: (0.30, 0.85, 0.45))
    static let good      = adaptive(light: (0.50, 0.37, 0.00), dark: (1.00, 0.80, 0.20))
    static let fair      = adaptive(light: (0.65, 0.26, 0.00), dark: (1.00, 0.55, 0.20))
    static let poor      = adaptive(light: (0.75, 0.08, 0.08), dark: (1.00, 0.45, 0.45))

    static func forLatency(_ latency: Double) -> Color {
        if latency < 20 { return excellent }
        if latency < 50 { return good }
        if latency < 100 { return fair }
        return poor
    }

    /// Probe-failure share for a session. Cloud gaming tolerates almost no
    /// loss, so 1% already reads as fair and 5% as poor.
    static func forPacketLoss(_ percent: Double) -> Color {
        if percent < 1 { return excellent }
        if percent < 5 { return fair }
        return poor
    }

    static func forQuality(_ quality: PingMonitor.Quality) -> Color {
        switch quality {
        case .excellent: return excellent
        case .good: return good
        case .fair: return fair
        case .poor: return poor
        }
    }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1.0)
        })
    }
}

private extension View {
    /// Share the system glass material across the dashboard's card surfaces.
    func dashboardCardStyle() -> some View {
        self
            .padding(DashboardLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DashboardCardBackground())
    }
}

private struct DashboardCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - Dashboard Settings Content

struct DashboardSettingsContent: View {
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject private var sessionCoordinator = ProtectedSessionCoordinator.shared

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer {
                    cardStack
                }
            } else {
                cardStack
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A Dashboard left open behind a fullscreen game kept redrawing
        // every sample. The probe keeps running for history and recaps;
        // only the redraw waits until the window can be seen again.
        .background(WindowVisibilityReader { visible in
            viewModel.setPresentationVisible(visible)
        })
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var cardStack: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
            ProtectedSessionCard(coordinator: sessionCoordinator)

            // Current Status Card
            StatusCard(viewModel: viewModel)

            // Ping Graph
            PingGraphCard(viewModel: viewModel, chart: viewModel.chart)

            // Latency Timeline
            LatencyTimelineCard(viewModel: viewModel)

            // AWDL Interventions Card
            InterventionsCard(viewModel: viewModel)

            // Which target the numbers above describe; editing lives in
            // Settings → Targets so the dashboard stays a read-out.
            TargetSummaryCard(viewModel: viewModel)
        }
    }
}

extension Notification.Name {
    static let pingWardenOpenSettingsSection = Notification.Name("PingWardenOpenSettingsSection")
}

// MARK: - Targets Settings Content

/// Settings → Targets. Owns its own view model like the dashboard does. It
/// shows no live latency, so its model starts without driving the shared
/// ping monitor or polling the helper.
struct TargetsSettingsContent: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        Form {
            ServerSelectionSettingsSection(viewModel: viewModel)
            CustomServersSettingsSection(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .onAppear { viewModel.start(includesTelemetry: false) }
        .onDisappear { viewModel.stop() }
    }
}

// MARK: - Window visibility

/// Reports whether the window hosting this view can be seen: on screen and
/// not covered, not in the Dock, and its app not hidden. SwiftUI's
/// onAppear and onDisappear do not fire for any of those.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> WindowVisibilityView {
        let view = WindowVisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowVisibilityView, context: Context) {
        nsView.onChange = onChange
    }
}

private final class WindowVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var lastReported: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        report()
    }

    private func observe(_ window: NSWindow?) {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        lastReported = nil
        guard let window else { return }

        let windowEvents: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        for name in windowEvents {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
        }
    }

    private func report() {
        guard let window else { return }
        let visible = PresentationVisibility.isVisible(
            windowOnScreen: window.occlusionState.contains(.visible),
            isMiniaturized: window.isMiniaturized,
            appIsHidden: NSApp.isHidden
        )
        guard visible != lastReported else { return }
        lastReported = visible
        // Deliver after the current view update; the handler publishes.
        let onChange = onChange
        DispatchQueue.main.async {
            onChange?(visible)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

struct TargetSummaryCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ping Target")
                    .font(.headline)
                if let target = viewModel.selectedTarget {
                    Text("\(target.displayName) · \(target.host):\(target.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No target selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button("Change…") {
                NotificationCenter.default.post(
                    name: .pingWardenOpenSettingsSection,
                    object: nil,
                    userInfo: ["section": "Targets"]
                )
            }
            .accessibilityHint("Opens the Targets settings pane")
        }
        .dashboardCardStyle()
    }
}

// MARK: - Protected sessions

struct ProtectedSessionCard: View {
    @ObservedObject var coordinator: ProtectedSessionCoordinator
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @State private var showingClearHistoryConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = protectionExperience.policyState

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Latency Session")
                        .font(.headline)
                    Text(coordinator.isActive ? activeSubtitle : "Measure one game or call from start to finish")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Group {
                    if coordinator.isActive {
                        Button("End Session") {
                            Task { await protectionExperience.endManualSession() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .keyboardShortcut(".", modifiers: [.command, .shift])
                    } else if state.licenseAllowsProtection {
                        Button("Start Session") {
                            Task { await protectionExperience.startManualSession() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    } else {
                        // Still offered, so the explanation it gives stays
                        // reachable, but not as the card's main action.
                        Button("Start Session") {
                            Task { await protectionExperience.startManualSession() }
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    }
                }
                .disabled(protectionExperience.isBusy)
            }

            if !coordinator.isActive {
                Label(
                    idleProtectionGuidance(state),
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !state.licenseAllowsProtection {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label("Latency sessions turn on Ping Protection, which needs a license.", systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Buy a License… · $15") {
                            NSWorkspace.shared.open(LicenseManager.purchaseURL)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            // Only the session's own errors belong here. Protection errors
            // show once, in the Ping Protection card.
            if let error = coordinator.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Latency session error: \(error)")
            }

            if coordinator.isActive {
                activeSessionBody
            } else if let summary = coordinator.latestSummary {
                SessionRecapView(summary: summary)
            } else {
                Label(
                    "Recaps stay on this Mac and never include hostnames, IP addresses, or game names.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !coordinator.history.isEmpty && !coordinator.isActive {
                let recentSessions = Array(coordinator.history.dropFirst())

                if !recentSessions.isEmpty {
                    DisclosureGroup("Recent Latency Sessions (\(recentSessions.count))") {
                        VStack(spacing: 8) {
                            if recentSessions.count > 5 {
                                Text("Last 5 of \(recentSessions.count) sessions")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ForEach(recentSessions.prefix(5)) { summary in
                                RecentSessionRow(summary: summary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption)
                }

                HStack {
                    Spacer()
                    Button("Clear Latency Session History", role: .destructive) {
                        showingClearHistoryConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .dashboardCardStyle()
        .confirmationDialog(
            "Clear Latency Session History?",
            isPresented: $showingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                coordinator.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved latency session recap from this Mac.")
        }
    }

    private var activeSubtitle: String {
        let trigger = coordinator.activeTrigger == .gameMode ? "Game Mode" : "Manual"
        return "\(trigger) session, \(Self.durationText(coordinator.elapsed))"
    }

    private func idleProtectionGuidance(_ state: ProtectionExperiencePolicy.State) -> String {
        if state.persistentProtectionEnabled {
            return "Ping Protection is already on and will stay on when the session ends."
        }
        return "Starting a session temporarily turns on Ping Protection, then turns it back off when the session ends."
    }

    private var activeSessionBody: some View {
        HStack(spacing: 12) {
            Group {
                if #available(macOS 14.0, *) {
                    if reduceMotion {
                        Image(systemName: "record.circle.fill")
                    } else {
                        Image(systemName: "record.circle.fill")
                            .symbolEffect(.pulse, options: .repeating)
                    }
                } else {
                    Image(systemName: "record.circle.fill")
                }
            }
            .foregroundStyle(.red)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Measuring latency locally")
                    .font(.subheadline)
                Text("Stopping creates a private recap without network addresses or raw samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latency session active for \(Self.durationText(coordinator.elapsed))")
    }

    fileprivate static func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, duration)) ?? "0m"
    }
}

private struct SessionRecapView: View {
    let summary: ProtectedSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latest Latency Session", systemImage: outcomeSymbol)
                    .font(.subheadline)
                    .foregroundStyle(outcomeColor)
                    .accessibilityValue(outcomeDescription)
                Spacer()
                if hasLatencyMeasurements {
                    ShareLink(item: summary.privacySafeShareText) {
                        Label("Share Recap", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Share a recap without network targets or raw samples")
                }
            }

            if hasLatencyMeasurements {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { metrics }
                    VStack(alignment: .leading, spacing: 8) { metrics }
                }

                Text("Intervention attempts count attempts to turn off AWDL. They do not confirm successful interventions or latency spikes prevented.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("Not Enough Measurements", systemImage: "chart.xyaxis.line")
                    .font(.subheadline)
                Text(insufficientMeasurementsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
    }

    private var hasLatencyMeasurements: Bool {
        summary.successfulSampleCount > 0
    }

    private var outcome: SessionRecapOutcome {
        SessionRecapOutcome.evaluate(
            successfulSampleCount: summary.successfulSampleCount,
            medianLatencyMs: summary.medianLatencyMs,
            packetLossPercent: summary.packetLossPercent
        )
    }

    /// The header grades the session instead of always showing a green
    /// check, which read as success after a poor session.
    private var outcomeSymbol: String {
        switch outcome {
        case .noMeasurements: return "questionmark.circle"
        case .good: return "checkmark.shield.fill"
        case .fair: return "exclamationmark.shield.fill"
        case .poor: return "xmark.shield.fill"
        }
    }

    private var outcomeColor: Color {
        switch outcome {
        case .noMeasurements: return .secondary
        case .good: return LatencyPalette.excellent
        case .fair: return LatencyPalette.fair
        case .poor: return LatencyPalette.poor
        }
    }

    private var outcomeDescription: String {
        switch outcome {
        case .noMeasurements: return "Not enough measurements"
        case .good: return "Good session"
        case .fair: return "Fair session"
        case .poor: return "Poor session"
        }
    }

    private var insufficientMeasurementsMessage: String {
        if summary.sampleCount == 0 {
            return "The recording stopped before the first latency probe finished."
        }
        return "The target did not return a successful latency measurement during this recording."
    }

    @ViewBuilder
    private var metrics: some View {
        SessionMetric(label: "Duration", value: ProtectedSessionCard.durationText(summary.duration))
        SessionMetric(
            label: "Median",
            value: String(format: "%.0f ms", summary.medianLatencyMs),
            tint: LatencyPalette.forLatency(summary.medianLatencyMs)
        )
        SessionMetric(
            label: "P95",
            value: String(format: "%.0f ms", summary.p95LatencyMs),
            helpText: "95% of successful latency measurements were at or below this value",
            tint: LatencyPalette.forLatency(summary.p95LatencyMs)
        )
        SessionMetric(label: "Jitter", value: String(format: "%.0f ms", summary.jitterMs))
        SessionMetric(
            label: "Probe Failures",
            value: String(format: "%.1f%%", summary.packetLossPercent),
            tint: LatencyPalette.forPacketLoss(summary.packetLossPercent)
        )
        SessionMetric(label: "Intervention Attempts", value: "\(summary.interventionCount)")
    }
}

private struct SessionMetric: View {
    let label: String
    let value: String
    var helpText: String? = nil
    /// Same palette the Network Quality card uses, so a bad session reads
    /// as bad at a glance. Nil keeps the neutral weight (Duration, Intervention Attempts).
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint ?? .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(helpText ?? "")
        .help(helpText ?? "\(label): \(value)")
    }
}

private struct RecentSessionRow: View {
    let summary: ProtectedSessionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.startedAt, format: .dateTime.month().day().hour().minute())
                Text("\(ProtectedSessionCard.durationText(summary.duration)), \(summary.sampleCount) samples")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(summary.interventionCount) intervention attempt\(summary.interventionCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status Card

struct StatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @ScaledMetric(relativeTo: .largeTitle) private var heroPingSize: CGFloat = 48

    var body: some View {
        // Read once per redraw; each read assembles the whole policy state.
        let isProtectionActive = protectionExperience.policyState.effectiveProtectionEnabled

        VStack(alignment: .leading, spacing: 14) {
            Text("Network Quality")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    currentPingBlock
                        .frame(minWidth: 120, alignment: .leading)

                    Divider()
                        .frame(height: 80)

                    metricGrid(isProtectionActive: isProtectionActive)
                }

                VStack(alignment: .leading, spacing: 16) {
                    currentPingBlock
                    Divider()
                    metricGrid(isProtectionActive: isProtectionActive)
                }
            }
        }
        .dashboardCardStyle()
    }

    private var currentPingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.latestProbeSucceeded {
            case nil:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Measuring…")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Measuring current latency")

            case false?:
                Label("Target Unreachable", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(LatencyPalette.poor)
                    .accessibilityLabel("Ping target unreachable")

            case true?:
                // ViewThatFits falls back to stacking the unit below the number
                // when the @ScaledMetric hero font grows past the card width
                // (AX5 + narrow Settings windows).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        pingValueText
                        pingUnitText
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        pingValueText
                        pingUnitText
                    }
                }

                Label(viewModel.stats.qualityDescription, systemImage: qualityIcon(viewModel.stats.quality))
                    .font(.subheadline)
                    .foregroundStyle(colorForQuality(viewModel.stats.quality))
            }

            if let selectedTarget = viewModel.selectedTarget {
                Text(selectedTarget.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(currentPingAccessibilityLabel)
    }

    private var pingValueText: some View {
        Text(String(format: "%.0f", viewModel.stats.currentPing))
            .font(.system(size: heroPingSize, weight: .bold, design: .rounded))
            .foregroundStyle(colorForQuality(viewModel.stats.quality))
            .contentTransition(.numericText())
    }

    private var pingUnitText: some View {
        Text("ms")
            .font(.title2)
            .foregroundStyle(.secondary)
    }

    private func metricGrid(isProtectionActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                MetricRow(label: "Average", value: latencyMetric(viewModel.stats.averagePing))
                MetricRow(label: "Best", value: latencyMetric(viewModel.stats.minimumPing))
                MetricRow(label: "Worst", value: latencyMetric(viewModel.stats.maximumPing))
            }

            VStack(alignment: .leading, spacing: 10) {
                MetricRow(label: "Jitter", value: latencyMetric(viewModel.stats.jitter, decimals: 1))
                MetricRow(label: "Probe Failures", value: probeFailureMetric)
                MetricRow(
                    label: "Protection",
                    value: isProtectionActive ? "Active" : "Off",
                    tint: isProtectionActive ? .green : .orange,
                    useMonospacedValue: false
                )
            }
        }
    }

    private var currentPingAccessibilityLabel: String {
        let target = viewModel.selectedTarget?.displayName ?? "selected target"
        switch viewModel.latestProbeSucceeded {
        case nil:
            return "Measuring current latency to \(target)"
        case false?:
            return "Ping target unreachable: \(target)"
        case true?:
            return "Current ping \(Int(viewModel.stats.currentPing.rounded())) milliseconds to \(target), network quality \(viewModel.stats.qualityDescription)"
        }
    }

    private func latencyMetric(_ value: Double, decimals: Int = 0) -> String {
        guard viewModel.hasSuccessfulProbe else { return "--" }
        return String(format: "%.*f ms", decimals, value)
    }

    private var probeFailureMetric: String {
        guard viewModel.latestProbeSucceeded != nil else { return "--" }
        return String(format: "%.1f%%", viewModel.stats.packetLoss)
    }
    
    private func colorForQuality(_ quality: PingMonitor.Quality) -> Color {
        LatencyPalette.forQuality(quality)
    }
    
    private func qualityIcon(_ quality: PingMonitor.Quality) -> String {
        switch quality {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "xmark.circle.fill"
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var tint: Color = .primary
    var useMonospacedValue: Bool = true

    /// Label-column width tracks the .caption font's Dynamic Type. At AX5
    /// the labels ("Probe Failures", "Average") need roughly 2x the room they
    /// do at default size; the previous fixed 74pt truncated long ones.
    @ScaledMetric(relativeTo: .caption) private var labelColumnWidth: CGFloat = 74

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)

            if useMonospacedValue {
                Text(value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(tint)
            } else {
                Text(value)
                    .font(.callout)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Ping Graph Card

struct PingGraphCard: View {
    /// Not observed: the card only writes the timeframe through it. Chart
    /// data arrives through `chart`, which publishes at about one bucket's
    /// width, so a sample that changes nothing on the chart does not make
    /// Swift Charts diff every mark again.
    let viewModel: DashboardViewModel
    @ObservedObject var chart: PingChartModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var emptyChartIconSize: CGFloat = 36

    // Static, so rebuilding this view for a parent redraw leaves its stored
    // fields identical and SwiftUI can skip the chart body.
    private static let timeframeOptions: [(minutes: Int, label: String)] = [
        (1, "1 min"),
        (5, "5 min"),
        (15, "15 min"),
        (30, "30 min"),
        (60, "1 hour")
    ]

    /// The line stays neutral; color marks the points by latency band. A
    /// line tinted by its newest sample drew earlier spikes in whatever
    /// color the latest reading happened to be.
    private static let lineColor = Color.secondary

    var body: some View {
        let snapshot = chart.snapshot

        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Ping History")
                        .font(.headline)

                    Spacer(minLength: 12)

                    timeframePicker
                        .frame(maxWidth: 390)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ping History")
                        .font(.headline)

                    timeframePicker
                        .frame(maxWidth: 390)
                }
            }

            Text("Showing the last \(timeframeLabel(for: snapshot.timeframeMinutes))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: emptyChartIconSize))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(emptyStateText(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
            } else {
                latencyChart(snapshot)
            }

            legend
        }
        .dashboardCardStyle()
    }

    private func latencyChart(_ snapshot: PingChartSnapshot) -> some View {
        Chart {
            ForEach(Self.latencyThresholds, id: \.value) { threshold in
                RuleMark(y: .value(threshold.label, threshold.value))
                    .foregroundStyle(threshold.color.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(snapshot.segments) { segment in
                ForEach(segment.points) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Ping", dataPoint.latencyMs),
                        series: .value("Successful Run", segment.id)
                    )
                    .foregroundStyle(Self.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }

            ForEach(snapshot.spikePoints) { dataPoint in
                PointMark(
                    x: .value("Time", dataPoint.timestamp),
                    y: .value("Ping", dataPoint.latencyMs)
                )
                .foregroundStyle(LatencyPalette.forLatency(dataPoint.latencyMs))
                .symbolSize(18)
            }

            if let latestPoint = snapshot.latestPoint {
                PointMark(
                    x: .value("Latest Time", latestPoint.timestamp),
                    y: .value("Latest Ping", latestPoint.latencyMs)
                )
                .foregroundStyle(LatencyPalette.forLatency(latestPoint.latencyMs))
                .symbolSize(42)
                .annotation(position: .top, alignment: .trailing) {
                    Text("\(Int(latestPoint.latencyMs.rounded())) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.35), in: Capsule())
                }
            }

            ForEach(snapshot.events) { event in
                RuleMark(x: .value("Event", event.timestamp))
                    .foregroundStyle(event.color.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            ForEach(snapshot.failedPoints) { dataPoint in
                RuleMark(x: .value("Failed Probe", dataPoint.timestamp))
                    .foregroundStyle(LatencyPalette.poor.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(
                    x: .value("Failed Probe Time", dataPoint.timestamp),
                    y: .value("Failed Probe", 0)
                )
                .foregroundStyle(LatencyPalette.poor)
                .symbolSize(34)
            }
        }
        .chartXScale(domain: snapshot.windowStart...snapshot.windowEnd)
        .chartYScale(domain: 0...snapshot.yUpperBound)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.trailing, 34)
        }
        .chartXAxis {
            // Clock-aligned ticks keep the same Date values from one redraw
            // to the next; see ChartTimeAxis for why that matters.
            AxisMarks(values: snapshot.tickDates) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        if ChartTimeAxis.labelsIncludeSeconds(forTimeframeMinutes: snapshot.timeframeMinutes) {
                            Text(date, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospacedDigit())
                        } else {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue) ms")
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 190)
        .accessibilityLabel("Ping latency chart")
        .accessibilityValue(chartAccessibilityValue)
        .accessibilityChartDescriptor(
            PingChartDescriptor(
                probeResults: snapshot.probePoints,
                timeframeMinutes: snapshot.timeframeMinutes
            )
        )
    }

    private func emptyStateText(_ snapshot: PingChartSnapshot) -> String {
        if !snapshot.hasAnyHistory {
            return "Collecting ping data…"
        }

        return "No successful ping samples in last \(timeframeLabel(for: snapshot.timeframeMinutes))."
    }

    /// Summary read by VoiceOver instead of the chart's default mark-by-mark
    /// announcements. Designed to give a sighted-equivalent snapshot in one
    /// breath: how many samples, current value, average, peak, and whether
    /// any timeline events occurred during the window. Counts come from the
    /// raw samples, not the thinned chart points.
    private var chartAccessibilityValue: String {
        let summary = chart.snapshot.summary
        let timeframe = timeframeLabel(for: chart.snapshot.timeframeMinutes)
        guard summary.probeCount > 0 else {
            return "No samples in the last \(timeframe)."
        }
        let failures = summary.probeCount - summary.successCount
        guard summary.successCount > 0 else {
            return "\(summary.probeCount) failed probe\(summary.probeCount == 1 ? "" : "s") in the last \(timeframe). The target did not return a successful latency measurement."
        }
        let current = Int(summary.currentMs.rounded())
        let avg = Int(summary.averageMs.rounded())
        let peak = Int(summary.peakMs.rounded())
        let events = summary.eventCount
        let eventPhrase = events == 0
            ? ""
            : ", with \(events) timeline event\(events == 1 ? "" : "s") in this window"
        let failurePhrase = failures == 0
            ? ""
            : ", and \(failures) failed probe\(failures == 1 ? "" : "s")"
        return "\(summary.successCount) successful samples over the last \(timeframe)\(failurePhrase). Current ping \(current) milliseconds, average \(avg), peak \(peak)\(eventPhrase)."
    }

    private func timeframeLabel(for minutes: Int) -> String {
        if minutes == 1 {
            return "1 minute"
        }
        if minutes == 60 {
            return "1 hour"
        }
        return "\(minutes) minutes"
    }

    private static let latencyThresholds: [(value: Double, label: String, color: Color)] = [
        (20, "Good", LatencyPalette.good),
        (50, "Fair", LatencyPalette.fair),
        (100, "Poor", LatencyPalette.poor)
    ]

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItems
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 6) {
                legendItems
            }
        }
        .font(.caption)
    }

    /// Each swatch matches its mark: dots for latency points, a dot for a
    /// failed probe, and a dashed line for timeline events.
    @ViewBuilder
    private var legendItems: some View {
        LegendItem(color: LatencyPalette.excellent, label: "Excellent", range: "<20 ms")
        LegendItem(color: LatencyPalette.good, label: "Good", range: "20–50 ms")
        LegendItem(color: LatencyPalette.fair, label: "Fair", range: "50–100 ms")
        LegendItem(color: LatencyPalette.poor, label: "Poor", range: "≥100 ms")
        ChartEventLegendItem(color: LatencyPalette.poor, swatch: .dot, label: "Failed probe")
        ChartEventLegendItem(color: .orange, swatch: .dashedLine, label: "Latency spike")
        ChartEventLegendItem(color: .green, swatch: .dashedLine, label: "Intervention attempt")
    }

    private var timeframePicker: some View {
        // The picker's own title is its VoiceOver label; a second
        // accessibilityLabel made VoiceOver read both.
        Picker(
            "Ping history timeframe",
            selection: Binding(
                get: { chart.snapshot.timeframeMinutes },
                set: { newTimeframe in
                    if reduceMotion {
                        viewModel.selectedTimeframe = newTimeframe
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedTimeframe = newTimeframe
                        }
                    }
                }
            )
        ) {
            ForEach(Self.timeframeOptions, id: \.minutes) { option in
                Text(option.label).tag(option.minutes)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let range: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(label) (\(range))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) range: \(range)")
    }
}

private struct ChartEventLegendItem: View {
    enum Swatch {
        case dot
        case dashedLine
    }

    let color: Color
    let swatch: Swatch
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch swatch {
                case .dot:
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                case .dashedLine:
                    DashedRuleSwatch()
                        .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 8, height: 12)
                }
            }
            .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// A short vertical line, drawn dashed to match the chart's event rules.
private struct DashedRuleSwatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// VoiceOver chart descriptor for `PingGraphCard`. Provides rotor-navigable
/// access to the ping time series so VoiceOver users can browse individual
/// samples instead of relying solely on the summary `accessibilityValue`.
private struct PingChartDescriptor: AXChartDescriptorRepresentable {
    let probeResults: [PingMonitor.PingResult]
    let timeframeMinutes: Int

    func makeChartDescriptor() -> AXChartDescriptor {
        let dataPoints = probeResults.filter(\.success)
        let failedProbes = probeResults.filter { !$0.success }
        let xs = dataPoints.map { $0.timestamp.timeIntervalSince1970 }
        let ys = dataPoints.map { $0.latencyMs }
        let allXs = probeResults.map { $0.timestamp.timeIntervalSince1970 }
        let xMin = allXs.min() ?? 0
        let xMax = allXs.max() ?? (xMin + 1)
        let yMax = max(100, ys.max() ?? 0)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: xMin...max(xMax, xMin + 1),
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                Date(timeIntervalSince1970: value)
                    .formatted(date: .omitted, time: .standard)
            }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Latency",
            range: 0...yMax,
            gridlinePositions: [],
            valueDescriptionProvider: { "\(Int($0)) milliseconds" }
        )
        var series: [AXDataSeriesDescriptor] = []
        if !dataPoints.isEmpty {
            series.append(AXDataSeriesDescriptor(
                name: "Ping latency",
                isContinuous: true,
                dataPoints: zip(xs, ys).map { AXDataPoint(x: $0.0, y: $0.1) }
            ))
        }
        if !failedProbes.isEmpty {
            series.append(AXDataSeriesDescriptor(
                name: "Failed probes",
                isContinuous: false,
                dataPoints: failedProbes.map {
                    AXDataPoint(x: $0.timestamp.timeIntervalSince1970, y: 0)
                }
            ))
        }
        return AXChartDescriptor(
            title: "Ping latency over time",
            summary: "Line chart of ping latency and failed probes over the last \(timeframeMinutes) minute\(timeframeMinutes == 1 ? "" : "s")",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: series
        )
    }
}

struct LatencyTimelineCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private static let visibleEventLimit = 8

    var body: some View {
        let events = viewModel.filteredTimelineEvents

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latency Timeline")
                    .font(.headline)
                Spacer()
                Text("Latency spikes and intervention attempts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if events.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("No notable events in selected timeframe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(events.suffix(Self.visibleEventLimit).reversed()) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: event.symbol)
                                .foregroundStyle(event.color)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.label)
                                    .font(.caption)
                                Text(event.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(event.label) at \(event.timestamp.formatted(date: .omitted, time: .standard))")
                    }

                    if events.count > Self.visibleEventLimit {
                        let hidden = events.count - Self.visibleEventLimit
                        Text("And \(hidden) earlier event\(hidden == 1 ? "" : "s") in this timeframe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dashboardCardStyle()
    }
}

// MARK: - Interventions Card

struct InterventionsCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @ScaledMetric(relativeTo: .largeTitle) private var heroCountSize: CGFloat = 48
    @State private var repairError: String?

    var body: some View {
        // Read once per redraw; each read assembles the whole policy state.
        let state = protectionExperience.policyState
        let toggleAction = ProtectionExperiencePolicy.toggleAction(for: state, now: Date())
        let isProtectionActive = state.effectiveProtectionEnabled
        let helperIsSilent = state.helperAvailable && !state.helperResponding

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ping Protection")
                    .font(.headline)
                Spacer()
                // Bordered, not prominent: Start Session is the page's
                // primary action, and two prominent buttons competed.
                Button(toggleAction.buttonTitle) {
                    changeProtectionState()
                }
                .buttonStyle(.bordered)
                .disabled(protectionExperience.isBusy || protectionExperience.isRepairingHelper)
                .accessibilityLabel(Self.accessibilityTitle(for: toggleAction))
            }

            if let error = protectionExperience.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if error.localizedCaseInsensitiveContains("license") {
                        Button("Buy a License… · $15") {
                            NSWorkspace.shared.open(LicenseManager.purchaseURL)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            if helperIsSilent || repairError != nil {
                repairRow(helperIsSilent: helperIsSilent)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 32) {
                    interventionCountBlock
                        .frame(width: 245, alignment: .leading)

                    interventionStatusBlock(isProtectionActive: isProtectionActive)
                        .frame(minWidth: 320, maxWidth: 560, alignment: .leading)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 14) {
                    interventionCountBlock
                    interventionStatusBlock(isProtectionActive: isProtectionActive)
                }
            }
        }
        .dashboardCardStyle()
    }

    /// The visible titles are short ("Turn On"); VoiceOver hears what they
    /// turn on.
    private static func accessibilityTitle(for action: ProtectionExperiencePolicy.ToggleAction) -> String {
        switch action {
        case .finishSetup: return "Finish Ping Protection Setup"
        case .turnOn: return "Turn On Ping Protection"
        case .turnOff: return "Turn Off Ping Protection"
        }
    }

    /// Offers the helper repair from Advanced settings right where the
    /// not-responding error appears.
    private func repairRow(helperIsSilent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if helperIsSilent {
                HStack(spacing: 8) {
                    Button {
                        repairHelper()
                    } label: {
                        if protectionExperience.isRepairingHelper {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Repairing…")
                            }
                        } else {
                            Text("Repair…")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(protectionExperience.isBusy || protectionExperience.isRepairingHelper)
                    .accessibilityLabel(protectionExperience.isRepairingHelper ? "Repairing helper connection" : "Repair helper connection")

                    Text("Reconnects the helper without changing your protection preference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let repairError {
                Label(repairError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The same repair path as Settings → Advanced → Repair: rebuild the
    /// helper's registration, then restore the saved protection preference.
    private func repairHelper() {
        repairError = nil
        let shouldRemainEnabled = PingWardenPreferences.shared.isMonitoringEnabled
        PingWardenMonitor.shared.repairHelperRegistration(presentsErrors: false) { repaired in
            Task { @MainActor in
                guard repaired else {
                    repairError = PingWardenMonitor.shared.lastSetupFailureMessage
                        ?? RepairResultCopy.failureMessage
                    return
                }
                let restored = await protectionExperience.setPersistentProtection(shouldRemainEnabled)
                if !restored {
                    repairError = "The helper is responding again, but Ping Warden could not restore your protection preference."
                }
            }
        }
    }

    /// Shares the menu's toggle decision, so the button's title and its
    /// action always agree.
    private func changeProtectionState() {
        switch protectionExperience.toggleAction() {
        case .finishSetup:
            // Repair registers a new helper, and also rebuilds one that is
            // approved but silent; registering alone could not fix that.
            PingWardenMonitor.shared.repairHelperRegistration { success in
                guard success else { return }
                Task { @MainActor in
                    await protectionExperience.setPersistentProtection(true)
                }
            }
        case .turnOn:
            Task {
                await protectionExperience.setPersistentProtection(true)
            }
        case .turnOff:
            Task {
                await protectionExperience.setPersistentProtection(false)
            }
        }
    }

    private var interventionCountBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intervention Attempts")
                .font(.caption)
                .foregroundStyle(.secondary)

            // ViewThatFits drops the attempt caption below
            // the hero count when the @ScaledMetric font + caption width
            // would overflow the card (AX5 + narrow windows).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    interventionCountText
                    interventionUnitText
                }
                VStack(alignment: .leading, spacing: 4) {
                    interventionCountText
                    interventionUnitText
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Intervention attempts recorded: \(viewModel.interventionCount)")
    }

    private var interventionCountText: some View {
        Text("\(viewModel.interventionCount)")
            .font(.system(size: heroCountSize, weight: .bold, design: .rounded))
            .foregroundStyle(.green)
            .contentTransition(.numericText())
    }

    private var interventionUnitText: some View {
        Text("attempts to turn off AWDL")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func interventionStatusBlock(isProtectionActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.interventionCount > 0 {
                // Green like the count beside it and the timeline's
                // intervention marker.
                Label("Intervention attempts recorded", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                Text("Ping Warden made \(viewModel.interventionCount) attempt\(viewModel.interventionCount == 1 ? "" : "s") to turn off AWDL. Attempts do not confirm successful interventions or latency spikes prevented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    isProtectionActive ? "No intervention attempts recorded" : "Protection is off",
                    systemImage: isProtectionActive ? "checkmark.shield" : "pause.circle"
                )
                .font(.subheadline)
                .foregroundStyle(isProtectionActive ? .green : .orange)

                Text(isProtectionActive ? "Ping Protection is active." : "Turn on Ping Protection to block AWDL activation attempts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(InnerCalloutBackground(cornerRadius: 8, fallbackOpacity: 0.28))
    }
}

/// Recessed callout styling within native dashboard content cards.
struct InnerCalloutBackground: ViewModifier {
    let cornerRadius: CGFloat
    let fallbackOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.background(
                .quaternary.opacity(fallbackOpacity),
                in: ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: true)
            )
        } else {
            content.background(
                .quaternary.opacity(fallbackOpacity),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

// MARK: - Server Selection Settings

struct ServerSelectionSettingsSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Section("Connection Settings") {
            Picker(selection: $viewModel.selectedTargetID) {
                ForEach(viewModel.targets) { target in
                    Text(target.displayName).tag(target.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ping Target")
                    if let selectedTarget = viewModel.selectedTarget {
                        Text("\(selectedTarget.host):\(selectedTarget.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Ping target")
            .help("Target used for latency measurements")
            .disabled(viewModel.targets.isEmpty)

            if viewModel.isRefreshingGFNServers {
                Text("Refreshing GeForce NOW zones…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let gfnRefreshError = viewModel.gfnRefreshError {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(gfnRefreshError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Retry") {
                        viewModel.refreshGeForceNOWTargetsOnDemand()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Retry refreshing GeForce NOW zones")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare available ping targets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let selectedTarget = viewModel.selectedTarget,
                       let baseline = viewModel.baselineLatencyResults[selectedTarget.id] {
                        Text(String(format: "Baseline %.0f ms", baseline))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    viewModel.autoSelectNearestEndpoint()
                } label: {
                    if viewModel.isAutoSelectingTarget {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Finding Fastest Target…")
                        }
                    } else {
                        Text("Find Fastest Target")
                    }
                }
                .controlSize(.small)
                .disabled(viewModel.isAutoSelectingTarget || viewModel.targets.isEmpty)
                .accessibilityLabel(
                    viewModel.isAutoSelectingTarget
                        ? "Finding fastest ping target"
                        : "Find fastest ping target"
                )
            }

            if let autoSelectionError = viewModel.autoSelectionError {
                Label(autoSelectionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Target selection error: \(autoSelectionError)")
            }

            Picker(selection: $viewModel.updateInterval) {
                Text("1 second").tag(TimeInterval(1))
                Text("2 seconds").tag(TimeInterval(2))
                Text("5 seconds").tag(TimeInterval(5))
                Text("10 seconds").tag(TimeInterval(10))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Interval")
                    Text("How often ping samples are captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Update interval")
        }
    }
}

// MARK: - Custom Ping Targets Settings

/// Lets the user add their own ping targets (issue #29). Persists through
/// `DashboardViewModel.addCustomTarget` / `removeCustomTarget` so the same
/// validation path runs whether input comes from this UI or from a future
/// import/config-file flow. Removal is undoable (Edit > Undo Remove Target)
/// instead of asking for confirmation.
struct CustomServersSettingsSection: View {
    private enum Field: Hashable {
        case name
        case host
        case port
    }

    @ObservedObject var viewModel: DashboardViewModel
    @State private var isAdding = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newPortText = "53"
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var validationErrorFocused: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Section {
            ForEach(viewModel.customTargets) { target in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.displayName)
                        Text("\(target.host):\(target.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        viewModel.removeCustomTarget(id: target.id, undoManager: undoManager)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(target.displayName)")
                    .help("Remove \(target.displayName)")
                }
            }

            if isAdding {
                TextField("Name", text: $newName, prompt: Text("For example, NextDNS"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .accessibilityLabel("Target name")

                TextField("Host", text: $newHost, prompt: Text("Hostname or IP address"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .host)
                    .accessibilityLabel("Target host")

                LabeledContent("Port") {
                    // The title is the field's VoiceOver label and 53 only
                    // the placeholder; the old title-as-placeholder read
                    // "53, Port".
                    TextField("Port", text: $newPortText, prompt: Text("53"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 80)
                        .focused($focusedField, equals: .port)
                        .onChangeCompat(of: newPortText) { newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue {
                                newPortText = filtered
                            }
                        }
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Validation error: \(validationMessage)")
                        .accessibilityFocused($validationErrorFocused)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        cancelAdd()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        commitAdd()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                HStack {
                    if viewModel.customTargets.isEmpty {
                        Text("No custom ping targets")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        beginAdd()
                    } label: {
                        Label("Add Target", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Custom Ping Targets")
        } footer: {
            Text("Add your own ping targets, such as a NextDNS or Control D server, to measure latency to hosts Ping Warden doesn’t include.")
        }
    }

    private func beginAdd() {
        newName = ""
        newHost = ""
        newPortText = "53"
        validationMessage = nil
        validationErrorFocused = false
        isAdding = true
        Task { @MainActor in
            focusedField = .name
        }
    }

    private func cancelAdd() {
        isAdding = false
        validationMessage = nil
        validationErrorFocused = false
        focusedField = nil
    }

    private func commitAdd() {
        let port = Int(newPortText) ?? 0
        let host = newHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (1...65_535).contains(port),
           viewModel.targets.contains(where: { $0.id == "\(host):\(port)" }) {
            showValidationError("A ping target with this host and port already exists.")
            return
        }

        if let failure = viewModel.addCustomTarget(displayName: newName, host: newHost, port: port) {
            switch failure {
            case .nameEmpty: focusedField = .name
            case .portOutOfRange: focusedField = .port
            case .hostEmpty, .hostTooLong, .hostInvalid: focusedField = .host
            }
            showValidationError(failure.userMessage)
            return
        }
        validationMessage = nil
        validationErrorFocused = false
        isAdding = false
        focusedField = nil
    }

    private func showValidationError(_ message: String) {
        validationErrorFocused = false
        validationMessage = message
        Task { @MainActor in
            validationErrorFocused = true
        }
    }
}

// MARK: - Previews

#Preview("Dashboard") {
    DashboardSettingsContent()
        .frame(width: 500, height: 700)
}

#Preview("Dashboard — Dynamic Type AX5") {
    DashboardSettingsContent()
        .frame(width: 500, height: 700)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dashboard — Light mode") {
    DashboardSettingsContent()
        .frame(width: 500, height: 700)
        .preferredColorScheme(.light)
}
