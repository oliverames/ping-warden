//
//  PingMonitor.swift
//  AWDLControl
//
//  Real-time network latency monitoring for cloud gaming.
//  Uses TCP connection timing as a proxy for ICMP ping.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import os.log

private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "PingMonitor")

/// Monitors network latency in real-time using TCP connection timing
/// Designed for cloud gaming - shows current ping, jitter, packet loss
class PingMonitor {
    
    // MARK: - Types
    
    struct PingResult: Identifiable {
        let id = UUID()
        let latency: TimeInterval  // in seconds
        let timestamp: Date
        let success: Bool
        
        var latencyMs: Double {
            latency * 1000.0
        }
    }
    
    enum Quality {
        case excellent  // <20ms
        case good       // 20-50ms
        case fair       // 50-100ms
        case poor       // >100ms or packet loss
        
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "yellow"
            case .fair: return "orange"
            case .poor: return "red"
            }
        }
        
        var description: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            }
        }
    }
    
    // MARK: - Properties
    
    private var timer: Timer?
    private var history: [PingResult] = []
    private let historyLock = NSLock()
    private let queue = DispatchQueue(label: "com.amesvt.pingwarden.pingmonitor", qos: .utility)
    private let statsWindowSeconds: TimeInterval = 120
    private let historyRetentionSeconds: TimeInterval = 3900 // Keep slightly over one hour
    private let connectionTimeoutSeconds: Int = 1
    
    /// Current server to ping
    var server: String = "8.8.8.8"
    
    /// Port to use for TCP ping (80 = HTTP, usually open)
    var port: UInt16 = 53
    
    /// Interval between pings (in seconds)
    var interval: TimeInterval = 2.0
    
    /// Callback when new ping result is available
    var onPingResult: ((PingResult) -> Void)?
    
    /// Callback when statistics are updated
    var onStatsUpdate: ((NetworkStatistics) -> Void)?
    
    // MARK: - Computed Properties
    
    var isMonitoring: Bool {
        return timer != nil
    }
    
    var currentPing: TimeInterval? {
        withHistoryLock {
            history.last?.latency
        }
    }
    
    var currentPingMs: Double? {
        currentPing.map { $0 * 1000.0 }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring with specified server and interval
    func start(server: String? = nil, port: UInt16? = nil, interval: TimeInterval? = nil) {
        if let server = server { self.server = server }
        if let port = port { self.port = port }
        if let interval = interval { self.interval = interval }
        
        guard !isMonitoring else {
            log.warning("Ping monitor already running")
            return
        }
        
        log.info("Starting ping monitor: \(self.server):\(self.port) every \(self.interval)s")
        
        // Perform immediate ping
        performPing()
        
        // Schedule repeating timer on main thread
        runOnMainThreadSync { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.performPing()
            }
            // Ensure timer continues during UI interactions
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    
    /// Stop monitoring
    func stop() {
        log.info("Stopping ping monitor")
        
        runOnMainThreadSync { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }
    
    /// Get current network statistics
    func getStatistics() -> NetworkStatistics {
        let recentResults = snapshotRecentResults()
        
        guard !recentResults.isEmpty else {
            return NetworkStatistics(
                currentPing: 0,
                averagePing: 0,
                minimumPing: 0,
                maximumPing: 0,
                jitter: 0,
                packetLoss: 0,
                quality: .poor
            )
        }
        
        let successfulPings = recentResults.filter { $0.success }
        let latencies = successfulPings.map { $0.latencyMs }
        
        let current = successfulPings.last?.latencyMs ?? 0
        let average = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let minimum = latencies.min() ?? 0
        let maximum = latencies.max() ?? 0
        
        // Calculate jitter (variance in latency)
        let jitter: Double
        if latencies.count > 1 {
            let diffs = zip(latencies.dropLast(), latencies.dropFirst()).map { abs($0.1 - $0.0) }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitter = 0
        }
        
        // Calculate packet loss
        let totalPings = recentResults.count
        let failedPings = recentResults.filter { !$0.success }.count
        let packetLoss = totalPings > 0 ? (Double(failedPings) / Double(totalPings)) * 100.0 : 0
        
        // Determine quality
        let quality: Quality
        if current == 0 || latencies.isEmpty {
            quality = .poor
        } else if current < 20 && packetLoss < 1.0 {
            quality = .excellent
        } else if current < 50 && packetLoss < 2.0 {
            quality = .good
        } else if current < 100 && packetLoss < 5.0 {
            quality = .fair
        } else {
            quality = .poor
        }
        
        return NetworkStatistics(
            currentPing: current,
            averagePing: average,
            minimumPing: minimum,
            maximumPing: maximum,
            jitter: jitter,
            packetLoss: packetLoss,
            quality: quality
        )
    }
    
    /// Get historical ping data for graphing
    func getHistory(lastMinutes: Int = 60) -> [PingResult] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(lastMinutes * 60))
        return withHistoryLock {
            history.filter { $0.timestamp > cutoff }
        }
    }
    
    /// Clear history
    func clearHistory() {
        withHistoryLock {
            history.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private func performPing() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Capture start time immediately before the TCP ping
            let startTime = Date()
            
            // Perform TCP connection timing
            let success = self.tcpPing(host: self.server, port: self.port)
            let endTime = Date()
            let latency = endTime.timeIntervalSince(startTime)
            let configuredInterval = self.interval
            
            let result = PingResult(
                latency: latency,
                timestamp: endTime,
                success: success
            )
            
            // Store in history
            self.addToHistory(result, interval: configuredInterval)
            
            // Notify callbacks on main thread
            DispatchQueue.main.async {
                self.onPingResult?(result)
                self.onStatsUpdate?(self.getStatistics())
            }
            
            if success {
                log.debug("Ping to \(self.server): \(String(format: "%.1f", result.latencyMs))ms")
            } else {
                log.warning("Ping to \(self.server) failed")
            }
        }
    }
    
    private func addToHistory(_ result: PingResult, interval: TimeInterval) {
        withHistoryLock {
            history.append(result)
            
            // Time-based retention keeps behavior consistent across intervals.
            let cutoff = Date().addingTimeInterval(-historyRetentionSeconds)
            history.removeAll { $0.timestamp < cutoff }
            
            // Cap history by expected sample volume to avoid unbounded growth.
            let effectiveInterval = max(interval, 0.2)
            let maxHistorySize = Int((historyRetentionSeconds / effectiveInterval).rounded(.up))
            if history.count > maxHistorySize {
                history.removeFirst(history.count - maxHistorySize)
            }
        }
    }
    
    /// Perform TCP connection timing (proxy for ICMP ping)
    /// Returns true if connection succeeded (regardless of actual latency)
    private func tcpPing(host: String, port: UInt16) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_NUMERICSERV,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        
        guard status == 0, let addrInfo = result else {
            if let result = result {
                freeaddrinfo(result)
            }
            return false
        }
        
        defer { freeaddrinfo(result) }
        
        // Create socket
        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            return false
        }
        
        defer { close(sock) }
        
        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
        
        // Attempt connection
        let connectResult = Darwin.connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        
        if connectResult == 0 {
            // Connected immediately (unlikely but possible)
            return true
        }
        
        if errno != EINPROGRESS {
            // Connection failed
            return false
        }
        
        // Wait for connection with timeout
        var readfds = fd_set()
        var writefds = fd_set()
        fdZero(&readfds)
        fdZero(&writefds)
        fdSet(sock, set: &writefds)
        
        var timeout = timeval(tv_sec: connectionTimeoutSeconds, tv_usec: 0)
        let selectResult = select(sock + 1, &readfds, &writefds, nil, &timeout)
        
        if selectResult <= 0 {
            // Timeout or error
            return false
        }
        
        // Check if connection succeeded
        var error: Int32 = 0
        var errorLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &errorLen)
        
        return error == 0
    }
    
    private func runOnMainThreadSync(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
    
    private func snapshotRecentResults() -> [PingResult] {
        withHistoryLock {
            let cutoff = Date().addingTimeInterval(-statsWindowSeconds)
            return history.filter { $0.timestamp > cutoff }
        }
    }
    
    @discardableResult
    private func withHistoryLock<T>(_ block: () -> T) -> T {
        historyLock.lock()
        defer { historyLock.unlock() }
        return block()
    }
    
    // MARK: - fd_set Helpers
    
    private func fdZero(_ set: inout fd_set) {
        set = fd_set()
    }
    
    private func fdSet(_ fd: Int32, set: inout fd_set) {
        // fd_set on Darwin uses fds_bits as a tuple of Int32 values
        // Each Int32 holds 32 file descriptors as bits
        let intOffset = Int(fd / 32)
        let bitOffset = Int(fd % 32)
        
        withUnsafeMutableBytes(of: &set.fds_bits) { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            let ptr = baseAddress.assumingMemoryBound(to: Int32.self)
            ptr[intOffset] |= Int32(1 << bitOffset)
        }
    }
}

// MARK: - Network Statistics

struct NetworkStatistics {
    let currentPing: Double      // milliseconds
    let averagePing: Double      // milliseconds
    let minimumPing: Double      // milliseconds
    let maximumPing: Double      // milliseconds
    let jitter: Double           // milliseconds (variance)
    let packetLoss: Double       // percentage (0-100)
    let quality: PingMonitor.Quality
    
    var qualityColor: String {
        quality.color
    }
    
    var qualityDescription: String {
        quality.description
    }
}
