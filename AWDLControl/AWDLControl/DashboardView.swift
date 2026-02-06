//
//  DashboardView.swift
//  AWDLControl
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

struct PingTarget: Identifiable, Hashable {
    enum Source: Int {
        case local
        case publicDNS
        case geforceNow
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

private enum DashboardConfig {
    static let intervalOptions: [TimeInterval] = [1, 2, 5, 10]
    static let timeframeOptions: [Int] = [5, 15, 30, 60]
    static let defaultInterval: TimeInterval = 2
    static let gfnRefreshCooldownSeconds: TimeInterval = 15
    static let selectedTargetKey = "DashboardSelectedPingTargetID"
    static let updateIntervalKey = "DashboardUpdateInterval"
    static let historyRetentionSeconds: TimeInterval = 3900
}

private enum LatencyPalette {
    static let excellent = Color(red: 0.16, green: 0.78, blue: 0.35)
    static let good = Color(red: 0.95, green: 0.72, blue: 0.05)
    static let fair = Color(red: 0.95, green: 0.49, blue: 0.12)
    static let poor = Color(red: 0.89, green: 0.20, blue: 0.18)
    
    static func forLatency(_ latency: Double) -> Color {
        if latency < 20 { return excellent }
        if latency < 50 { return good }
        if latency < 100 { return fair }
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
}

private enum NetworkGatewayResolver {
    static func defaultGatewayAddress() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
        process.arguments = ["-n", "get", "default"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("gateway:") else { continue }
            
            let gateway = line.replacingOccurrences(of: "gateway:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !gateway.isEmpty, !gateway.hasPrefix("link#") else {
                return nil
            }
            
            return gateway
        }
        
        return nil
    }
}

private enum GeForceNOWDiscovery {
    private static let endpoint = URL(string: "https://status.geforcenow.com/api/v2/components.json")
    private static let zoneCodePattern = #"\bNP[A]?-[A-Z0-9-]+\b"#
    
    private struct ComponentsResponse: Decodable {
        let components: [Component]
    }
    
    private struct Component: Decodable {
        let name: String
    }
    
    static func fetchTargets() async -> [PingTarget] {
        guard let endpoint else { return [] }
        
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            let payload = try JSONDecoder().decode(ComponentsResponse.self, from: data)
            let codes = extractZoneCodes(from: payload.components.map(\.name))
            
            return codes.sorted().map { code in
                PingTarget(
                    displayName: "GeForce NOW (\(code))",
                    host: "\(code.lowercased()).cloudmatchbeta.nvidiagrid.net",
                    port: 443,
                    source: .geforceNow
                )
            }
        } catch {
            return []
        }
    }
    
    private static func extractZoneCodes(from componentNames: [String]) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: zoneCodePattern) else {
            return []
        }
        
        var codes = Set<String>()
        
        for name in componentNames {
            let uppercasedName = name.uppercased()
            let nameNSString = uppercasedName as NSString
            let range = NSRange(location: 0, length: nameNSString.length)
            let matches = regex.matches(in: uppercasedName, range: range)
            
            for match in matches {
                codes.insert(nameNSString.substring(with: match.range))
            }
        }
        
        return codes
    }
}

// MARK: - Dashboard Settings Content

struct DashboardSettingsContent: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Current Status Card
                StatusCard(viewModel: viewModel)
                
                // Ping Graph
                PingGraphCard(viewModel: viewModel)
                
                // AWDL Interventions Card
                InterventionsCard(viewModel: viewModel)
                
                // Server Selection
                ServerSelectionCard(viewModel: viewModel)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Quality")
                .font(.headline)
            
            HStack(spacing: 24) {
                // Current Ping - Main display
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", viewModel.stats.currentPing))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(colorForQuality(viewModel.stats.quality))
                            .contentTransition(.numericText())
                        Text("ms")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label(viewModel.stats.qualityDescription, systemImage: qualityIcon(viewModel.stats.quality))
                        .font(.subheadline)
                        .foregroundStyle(colorForQuality(viewModel.stats.quality))
                }
                .frame(minWidth: 120)
                
                Divider()
                    .frame(height: 80)
                
                // Stats Grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Average")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text(String(format: "%.0f ms", viewModel.stats.averagePing))
                            .font(.callout.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                        Text("Jitter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                        Text(String(format: "%.1f ms", viewModel.stats.jitter))
                            .font(.callout.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Text("Best")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f ms", viewModel.stats.minimumPing))
                            .font(.callout.monospacedDigit())
                        Text("Packet Loss")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", viewModel.stats.packetLoss))
                            .font(.callout.monospacedDigit())
                    }
                    GridRow {
                        Text("Worst")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f ms", viewModel.stats.maximumPing))
                            .font(.callout.monospacedDigit())
                        Text("AWDL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.isAWDLBlocking ? "Blocking" : "Allowed")
                            .font(.callout)
                            .foregroundStyle(viewModel.isAWDLBlocking ? .green : .orange)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Ping Graph Card

struct PingGraphCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    private let timeframeOptions: [(minutes: Int, label: String)] = [
        (5, "5 min"),
        (15, "15 min"),
        (30, "30 min"),
        (60, "1 hour")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ping History")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(timeframeOptions, id: \.minutes) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectedTimeframe = option.minutes
                            }
                        } label: {
                            Text(option.label)
                                .font(.headline)
                                .foregroundStyle(viewModel.selectedTimeframe == option.minutes ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    viewModel.selectedTimeframe == option.minutes
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Show \(option.label) ping history")
                    }
                }
            }
            
            if viewModel.filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(emptyStateText())
                        .foregroundStyle(.secondary)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            } else {
                Chart(viewModel.filteredHistory) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Ping", dataPoint.latencyMs)
                    )
                    .foregroundStyle(colorForLatency(dataPoint.latencyMs))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    AreaMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Ping", dataPoint.latencyMs)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colorForLatency(dataPoint.latencyMs).opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    PointMark(
                        x: .value("Time", dataPoint.timestamp),
                        y: .value("Ping", dataPoint.latencyMs)
                    )
                    .foregroundStyle(colorForLatency(dataPoint.latencyMs))
                    .symbolSize(14)
                }
                .chartYScale(domain: 0...max(100, viewModel.maxPingInView))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.hour().minute())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
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
                .frame(height: 180)
            }
            
            // Legend
            HStack(spacing: 16) {
                LegendItem(color: LatencyPalette.excellent, label: "Excellent", range: "<20ms")
                LegendItem(color: LatencyPalette.good, label: "Good", range: "20-50ms")
                LegendItem(color: LatencyPalette.fair, label: "Fair", range: "50-100ms")
                LegendItem(color: LatencyPalette.poor, label: "Poor", range: ">100ms")
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func emptyStateText() -> String {
        if viewModel.pingHistory.isEmpty {
            return "Collecting ping data..."
        }
        
        return "No successful ping samples in last \(timeframeLabel(for: viewModel.selectedTimeframe))."
    }
    
    private func timeframeLabel(for minutes: Int) -> String {
        if minutes == 60 {
            return "1 hour"
        }
        return "\(minutes) minutes"
    }
    
    private func colorForLatency(_ latency: Double) -> Color {
        LatencyPalette.forLatency(latency)
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
            Text("\(label) (\(range))")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interventions Card

struct InterventionsCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AWDL Protection")
                .font(.headline)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interventions Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(viewModel.interventionCount)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("lag spikes")
                            Text("prevented")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if viewModel.interventionCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AWDL tried to activate", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        
                        Text("Ping Warden blocked it \(viewModel.interventionCount) times to keep your connection stable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Server Selection Card

struct ServerSelectionCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ping Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Server", selection: $viewModel.selectedTargetID) {
                        ForEach(viewModel.targets) { target in
                            Text(target.displayName).tag(target.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 260)
                    .disabled(viewModel.targets.isEmpty)
                    .onTapGesture {
                        viewModel.refreshGeForceNOWTargetsOnDemand()
                    }
                    
                    if let selectedTarget = viewModel.selectedTarget {
                        Text("\(selectedTarget.host):\(selectedTarget.port)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if viewModel.isRefreshingGFNServers {
                        Text("Refreshing GeForce NOW zones...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Update Interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Interval", selection: $viewModel.updateInterval) {
                        Text("1 second").tag(TimeInterval(1))
                        Text("2 seconds").tag(TimeInterval(2))
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 120)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dashboard ViewModel

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var stats = NetworkStatistics(
        currentPing: 0,
        averagePing: 0,
        minimumPing: 0,
        maximumPing: 0,
        jitter: 0,
        packetLoss: 0,
        quality: .poor
    )
    
    @Published var pingHistory: [PingMonitor.PingResult] = []
    @Published var interventionCount: Int = 0
    @Published var isAWDLBlocking: Bool = false
    @Published var selectedTimeframe: Int = 15 { // minutes
        didSet {
            if !DashboardConfig.timeframeOptions.contains(selectedTimeframe) {
                selectedTimeframe = 15
            }
        }
    }
    @Published private(set) var targets: [PingTarget] = []
    @Published var selectedTargetID: String = "" {
        didSet {
            guard selectedTargetID != oldValue else { return }
            userDefaults.set(selectedTargetID, forKey: DashboardConfig.selectedTargetKey)
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
    
    private let pingMonitor = PingMonitor()
    private var interventionTimer: Timer?
    private var gfnRefreshTask: Task<Void, Never>?
    private var isStarted = false
    private var gfnTargets: [PingTarget] = []
    private var lastGFNRefreshDate: Date = .distantPast
    
    private let userDefaults = UserDefaults.standard
    
    var selectedTarget: PingTarget? {
        targets.first { $0.id == selectedTargetID }
    }
    
    /// Filtered ping history based on selected timeframe
    var filteredHistory: [PingMonitor.PingResult] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(selectedTimeframe * 60))
        return pingHistory.filter { $0.timestamp > cutoff && $0.success }
    }
    
    var maxPingInView: Double {
        let max = filteredHistory.map(\.latencyMs).max() ?? 0
        // Add some headroom and ensure minimum scale
        return Swift.max(100, max * 1.1)
    }
    
    init() {
        let gateway = NetworkGatewayResolver.defaultGatewayAddress()
        targets = Self.baseTargets(localGateway: gateway)
        
        if let savedInterval = userDefaults.object(forKey: DashboardConfig.updateIntervalKey) as? Double {
            updateInterval = sanitizedInterval(savedInterval)
        }
        
        if let savedTargetID = normalizedSavedTargetID(userDefaults.string(forKey: DashboardConfig.selectedTargetKey)),
           targets.contains(where: { $0.id == savedTargetID }) {
            selectedTargetID = savedTargetID
        } else {
            selectedTargetID = targets.first(where: { $0.source == .local })?.id ?? targets.first?.id ?? ""
        }
    }
    
    func start() {
        guard !isStarted else { return }
        isStarted = true
        
        // Start ping monitoring
        pingMonitor.onPingResult = { [weak self] result in
            Task { @MainActor in
                self?.handlePingResult(result)
            }
        }
        
        pingMonitor.onStatsUpdate = { [weak self] stats in
            Task { @MainActor in
                self?.stats = stats
            }
        }
        
        startMonitoring(clearHistory: false)
        
        // Update AWDL status
        updateAWDLStatus()
        
        // Start intervention counter updates
        updateInterventionCount()
        interventionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateInterventionCount()
                self?.updateAWDLStatus()
            }
        }
        
    }
    
    func stop() {
        isStarted = false
        pingMonitor.stop()
        interventionTimer?.invalidate()
        interventionTimer = nil
        gfnRefreshTask?.cancel()
        gfnRefreshTask = nil
        isRefreshingGFNServers = false
    }
    
    private func restartMonitoring() {
        guard isStarted else { return }
        startMonitoring(clearHistory: true)
    }
    
    private func startMonitoring(clearHistory: Bool) {
        guard let target = selectedTarget else { return }
        
        pingMonitor.stop()
        
        if clearHistory {
            pingMonitor.clearHistory()
            pingHistory.removeAll()
        }
        
        pingMonitor.start(server: target.host, port: target.port, interval: updateInterval)
    }
    
    private func handlePingResult(_ result: PingMonitor.PingResult) {
        pingHistory.append(result)
        
        // Keep only a bit over one hour of data to support all dashboard windows.
        let cutoff = Date().addingTimeInterval(-DashboardConfig.historyRetentionSeconds)
        pingHistory.removeAll { $0.timestamp < cutoff }
    }
    
    private func updateInterventionCount() {
        AWDLMonitor.shared.getInterventionCount { [weak self] count in
            Task { @MainActor in
                self?.interventionCount = count
            }
        }
    }
    
    private func updateAWDLStatus() {
        isAWDLBlocking = AWDLMonitor.shared.isMonitoringActive
    }
    
    func refreshGeForceNOWTargetsOnDemand() {
        refreshGeForceNOWTargets(force: true)
    }
    
    private func refreshGeForceNOWTargets(force: Bool) {
        if !force,
           Date().timeIntervalSince(lastGFNRefreshDate) < DashboardConfig.gfnRefreshCooldownSeconds {
            return
        }
        
        gfnRefreshTask?.cancel()
        isRefreshingGFNServers = true
        lastGFNRefreshDate = Date()
        
        gfnRefreshTask = Task { [weak self] in
            let discoveredTargets = await GeForceNOWDiscovery.fetchTargets()
            
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.isRefreshingGFNServers = false
                self.gfnTargets = discoveredTargets
                self.rebuildTargets()
            }
        }
    }
    
    private func rebuildTargets() {
        let gatewayHost = targets.first(where: { $0.source == .local })?.host ?? NetworkGatewayResolver.defaultGatewayAddress()
        let baseTargets = Self.baseTargets(localGateway: gatewayHost)
        let sortedGFNTargets = gfnTargets.sorted { $0.displayName < $1.displayName }
        
        var deduplicatedTargets: [PingTarget] = []
        var seenIDs = Set<String>()
        
        for target in baseTargets + sortedGFNTargets {
            if seenIDs.insert(target.id).inserted {
                deduplicatedTargets.append(target)
            }
        }
        
        targets = deduplicatedTargets
        
        if !targets.contains(where: { $0.id == selectedTargetID }) {
            selectedTargetID = targets.first(where: { $0.source == .local })?.id ?? targets.first?.id ?? ""
        }
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
            displayName: "Google DNS (Global)",
            host: "8.8.8.8",
            port: 53,
            source: .publicDNS
        ))
        
        targets.append(PingTarget(
            displayName: "GeForce NOW Routing API",
            host: "prod.cloudmatchbeta.nvidiagrid.net",
            port: 443,
            source: .geforceNow
        ))
        
        return targets
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
}

// MARK: - Previews

#Preview("Dashboard") {
    DashboardSettingsContent()
        .frame(width: 500, height: 700)
}
