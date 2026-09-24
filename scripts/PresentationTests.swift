import Foundation

// INSERT_SECTION

extension Notification.Name {
    static let pingWardenOpenSettingsSection = Notification.Name("PingWardenOpenSettingsSection")
}

@MainActor final class Navigation {
    var selectedSection: SettingsSection = .general
}

// No AppDelegate startup, NSApplication, preferences, networking, or services.
@MainActor final class ObserverHost {
    let settingsNavigation = Navigation()
    var openedSections: [SettingsSection] = []
    func openSettings() {
        MainActor.assertIsolated()
        openedSections.append(settingsNavigation.selectedSection)
    }
    func start() { installSettingsSectionObserver() }
    // INSERT_OBSERVER
}

struct LatencyTimelineEvent {
    // INSERT_KIND
    let timestamp: Date
    let kind: Kind
}

enum PingMonitor {
    struct PingResult {
        let timestamp: Date
        let latencyMs: Double
        let success: Bool
    }
}

final class ChartModel {
    var selectedTimeframe = 1
    var timelineEvents: [LatencyTimelineEvent] = []
    var pingHistory: [PingMonitor.PingResult] = []
    var filteredProbeHistory: [PingMonitor.PingResult] = []
    var filteredHistory: [PingMonitor.PingResult] = []
    private static let maxChartPoints = 720
    func refresh() { refreshFilteredHistory() }
    // INSERT_EVENTS
    // INSERT_REFRESH
    // INSERT_DOWNSAMPLE
}

struct ChartHost {
    let viewModel: ChartModel
    var summary: String { chartAccessibilityValue }
    // INSERT_SUMMARY
    // INSERT_TIMEFRAME
}

// An inert verifier holds requests until the test explicitly settles them.
@MainActor final class SubmissionVerifier {
    var isVerifying = false
    var keys: [String] = []
    var continuation: CheckedContinuation<Bool, Never>?
    func verify(key: String) async -> Bool {
        isVerifying = true
        keys.append(key)
        let result = await withCheckedContinuation { continuation = $0 }
        isVerifying = false
        return result
    }
    func finish(_ result: Bool) { continuation?.resume(returning: result); continuation = nil }
}
@MainActor final class SubmissionHost {
    let license = SubmissionVerifier()
    var keyField = ""
    var licenseMessage: String?
    let licenseMessageForLastResult = "Offline fixture"
    func submit() { submitLicenseKey() }
    // INSERT_SUBMIT
}

final class CustomTargetHost {
    let customTargetStore: CustomPingTargetStore
    var customTargets: [CustomPingTarget] = []
    var rebuildCount = 0
    init(defaults: UserDefaults) { customTargetStore = CustomPingTargetStore(userDefaults: defaults) }
    func rebuildTargets() { rebuildCount += 1 }
    // INSERT_ADD_TARGET
}

@main struct PresentationTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        checks += 1
        print("PASS: \(message)")
    }
    @MainActor static func settle() async {
        try! await Task.sleep(nanoseconds: 25_000_000)
    }
    @MainActor static func main() async {
        let suite = "PingWarden.PresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let targets = CustomTargetHost(defaults: defaults)
        check(targets.addCustomTarget(displayName: "Kept", host: "localhost", port: 53) == nil,
              "valid custom target persists through production submission")
        let stored = defaults.data(forKey: "DashboardCustomPingTargets")
        check(targets.addCustomTarget(displayName: "Rejected", host: "https://example.com/path", port: 53) == .hostInvalid,
              "production submission rejects URL before saving")
        check(defaults.data(forKey: "DashboardCustomPingTargets") == stored && targets.rebuildCount == 1,
              "rejected target leaves persisted and displayed targets unchanged")
        let submission = SubmissionHost()
        submission.keyField = " \n "
        submission.submit()
        await settle()
        check(submission.license.keys.isEmpty, "empty Return submission never reaches verifier")
        submission.keyField = "synthetic-key"
        submission.submit()
        submission.submit()
        await settle()
        check(submission.license.keys == ["synthetic-key"], "queued Return/click submissions start only one verification")
        submission.submit()
        await settle()
        check(submission.license.keys.count == 1, "in-flight submission stays disabled")
        submission.license.finish(false)
        await settle()
        check(submission.licenseMessage == "Offline fixture", "failed verification presents its result")
        check(submission.keyField == "synthetic-key", "failed verification preserves entered key")
        submission.submit()
        await settle()
        submission.keyField = "edited-during-request"
        submission.license.finish(true)
        await settle()
        check(submission.keyField == "edited-during-request", "successful earlier request preserves newer editing")
        submission.submit()
        await settle()
        submission.license.finish(true)
        await settle()
        check(submission.keyField.isEmpty, "successful verification clears its own submitted key")

        let host = ObserverHost()
        host.start()
        NotificationCenter.default.post(name: .pingWardenOpenSettingsSection, object: nil,
                                        userInfo: ["section": "Targets"])
        await settle()
        check(host.settingsNavigation.selectedSection == .targets, "Targets notification selects Targets")
        check(host.openedSections == [.targets], "opening observes selected pane on main actor")
        for payload: [String: Any] in [[:], ["section": 7], ["section": "Unknown"]] {
            NotificationCenter.default.post(name: .pingWardenOpenSettingsSection, object: nil, userInfo: payload)
        }
        await settle()
        check(host.openedSections.count == 1, "missing, malformed, unknown section do not open settings")
        for _ in 0..<2 {
            NotificationCenter.default.post(name: .pingWardenOpenSettingsSection, object: nil,
                                            userInfo: ["section": "Targets"])
            await settle()
        }
        check(host.openedSections == [.targets, .targets, .targets], "repeated valid requests remain usable")
        NotificationCenter.default.post(name: .pingWardenOpenSettingsSection, object: nil,
                                        userInfo: ["section": "Advanced"])
        await settle()
        check(host.openedSections.last == .advanced, "subsequent request switches pane before opening")

        let model = ChartModel()
        let chart = ChartHost(viewModel: model)
        check(chart.summary == "No samples in the last 1 minute.", "empty chart summary")
        let now = Date()
        model.pingHistory = [.init(timestamp: now, latencyMs: 150, success: true)]
        model.refresh()
        model.timelineEvents = [.init(timestamp: now, kind: .latencySpike(latencyMs: 150))]
        check(chart.summary.contains("with 1 timeline event in this window"), "spike-only chart has neutral singular event wording")
        check(!chart.summary.contains("protection"), "latency spike does not imply protection")
        model.timelineEvents = [.init(timestamp: now, kind: .awdlIntervention(delta: 8))]
        check(chart.summary.contains("with 1 timeline event in this window"), "aggregated intervention is one timeline entry, not eight")
        model.timelineEvents.append(.init(timestamp: now, kind: .latencySpike(latencyMs: 150)))
        check(chart.summary.contains("with 2 timeline events in this window"), "mixed events use neutral plural wording")
        model.timelineEvents.append(.init(timestamp: now.addingTimeInterval(-120), kind: .latencySpike(latencyMs: 200)))
        model.pingHistory.append(.init(timestamp: now.addingTimeInterval(-120), latencyMs: 999, success: true))
        model.refresh()
        check(model.filteredTimelineEvents.count == 2 && model.filteredProbeHistory.count == 1,
              "production filtering excludes old events and probes")
        check(chart.summary.contains("peak 150, with 2 timeline events"), "old spike does not affect current summary")
        model.timelineEvents = [.init(timestamp: now.addingTimeInterval(-120), kind: .awdlIntervention(delta: 12))]
        check(!chart.summary.contains("timeline event"), "out-of-window-only events omit event phrase")
        model.pingHistory.append(.init(timestamp: now, latencyMs: 0, success: false))
        model.refresh()
        check(chart.summary.contains("and 1 failed probe"), "mixed probe failures remain announced")
        model.pingHistory = [.init(timestamp: now, latencyMs: 0, success: false)]
        model.refresh()
        check(chart.summary.contains("1 failed probe in the last 1 minute"), "all-failed window remains truthful")
        check(!chart.summary.contains("Current ping"), "all-failed window has no fabricated latency")
        print("\(checks) presentation checks passed; no application lifecycle or production state used.")
    }
}
