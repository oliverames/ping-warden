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

import SwiftUI
import Charts

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
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        StatLabel(label: "Average")
                        StatValue(value: String(format: "%.0f ms", viewModel.stats.averagePing))
                        StatLabel(label: "Jitter")
                        StatValue(value: String(format: "%.1f ms", viewModel.stats.jitter))
                    }
                    GridRow {
                        StatLabel(label: "Best")
                        StatValue(value: String(format: "%.0f ms", viewModel.stats.minimumPing))
                        StatLabel(label: "Packet Loss")
                        StatValue(value: String(format: "%.1f%%", viewModel.stats.packetLoss))
                    }
                    GridRow {
                        StatLabel(label: "Worst")
                        StatValue(value: String(format: "%.0f ms", viewModel.stats.maximumPing))
                        StatLabel(label: "AWDL")
                        StatValue(
                            value: viewModel.isAWDLBlocking ? "Blocking" : "Allowed",
                            color: viewModel.isAWDLBlocking ? .green : .orange
                        )
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func colorForQuality(_ quality: PingMonitor.Quality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .yellow
        case .fair: return .orange
        case .poor: return .red
        }
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

struct StatLabel: View {
    let label: String
    
    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
    }
}

struct StatValue: View {
    let value: String
    var color: Color = .primary
    
    var body: some View {
        Text(value)
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .frame(width: 80, alignment: .trailing)
    }
}

// MARK: - Ping Graph Card

struct PingGraphCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ping History")
                    .font(.headline)
                
                Spacer()
                
                Picker("Timeframe", selection: $viewModel.selectedTimeframe) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            
            if viewModel.filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Collecting ping data...")
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
                LegendItem(color: .green, label: "Excellent", range: "<20ms")
                LegendItem(color: .yellow, label: "Good", range: "20-50ms")
                LegendItem(color: .orange, label: "Fair", range: "50-100ms")
                LegendItem(color: .red, label: "Poor", range: ">100ms")
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func colorForLatency(_ latency: Double) -> Color {
        if latency < 20 { return .green }
        if latency < 50 { return .yellow }
        if latency < 100 { return .orange }
        return .red
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
                    
                    Picker("Server", selection: $viewModel.selectedServer) {
                        Text("Google DNS (Global)").tag("8.8.8.8")
                        Text("Cloudflare (Global)").tag("1.1.1.1")
                        Text("GeForce NOW (US West)").tag("gfn-us-west.nvidia.com")
                        Text("GeForce NOW (US East)").tag("gfn-us-east.nvidia.com")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Update Interval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Interval", selection: $viewModel.updateInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
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
    @Published var selectedTimeframe: Int = 15 // minutes
    @Published var selectedServer: String = "8.8.8.8" {
        didSet {
            if selectedServer != oldValue {
                restartMonitoring()
            }
        }
    }
    @Published var updateInterval: TimeInterval = 2.0 {
        didSet {
            if updateInterval != oldValue {
                restartMonitoring()
            }
        }
    }
    
    private let pingMonitor = PingMonitor()
    private var interventionTimer: Timer?
    
    /// Filtered ping history based on selected timeframe
    var filteredHistory: [PingMonitor.PingResult] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(selectedTimeframe * 60))
        return pingHistory.filter { $0.timestamp > cutoff }
    }
    
    var maxPingInView: Double {
        let max = filteredHistory.map(\.latencyMs).max() ?? 0
        // Add some headroom and ensure minimum scale
        return Swift.max(100, max * 1.1)
    }
    
    func start() {
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
        
        pingMonitor.start(server: selectedServer, interval: updateInterval)
        
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
        pingMonitor.stop()
        interventionTimer?.invalidate()
        interventionTimer = nil
    }
    
    private func restartMonitoring() {
        pingMonitor.stop()
        pingMonitor.clearHistory()
        pingHistory.removeAll()
        pingMonitor.start(server: selectedServer, interval: updateInterval)
    }
    
    private func handlePingResult(_ result: PingMonitor.PingResult) {
        pingHistory.append(result)
        
        // Keep only data for selected timeframe plus a bit extra
        let cutoff = Date().addingTimeInterval(-TimeInterval(selectedTimeframe * 60 + 300))
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
}
