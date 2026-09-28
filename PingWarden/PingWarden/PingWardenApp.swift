//
//  PingWardenApp.swift
//  PingWarden
//
//  Main application entry point and UI for Ping Warden.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import SwiftUI
import ServiceManagement
import os.log
import Sparkle
import Network

private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "App")

// MARK: - Backward Compatible onChange

extension View {
    /// Backward-compatible onChange modifier that works on macOS 13 and later
    /// Uses the new two-parameter closure on macOS 14+, falls back to old API on macOS 13
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

@main
struct PingWardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Intentionally empty, and intentionally WITHOUT a fixed .frame().
            //
            // This Settings scene exists only to host the app-settings command
            // group below — the real preferences UI is an AppKit-managed
            // NSWindow (see AppDelegate.showSettingsWindow), so this scene's
            // window is a hidden phantom that is never presented.
            //
            // The previous `EmptyView().frame(width: 1, height: 1)` pinned that
            // phantom window's content to a 1pt-wide hard constraint. On
            // macOS 26+ that degenerate geometry drives the backing
            // NSHostingView into a re-entrant Update-Constraints-in-Window loop
            // and crashes with NSGenericException ("...more Update Constraints
            // in Window passes than there are views in the window"). The crash
            // report's window bounds literally read width 1, matching the old
            // frame. Letting the empty content size itself removes the
            // conflicting constraint and the loop.
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ping Warden") {
                    appDelegate.openAbout()
                }
            }
            // Declared here rather than inserted into NSApp.mainMenu, which
            // SwiftUI rebuilds and so dropped the item.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.checkForUpdates()
                }
            }
            PingWardenHelpCommands(appDelegate: appDelegate)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Observe the offer at the command boundary so changes after app launch
/// update the Help menu even though the Settings scene hosts no window.
@MainActor
struct PingWardenHelpCommands: Commands {
    @ObservedObject var appDelegate: AppDelegate

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Ping Warden Help", destination: LicenseManager.documentationURL)
            Link("Troubleshooting", destination: LicenseManager.troubleshootingURL)
            Link("Ping Warden Website", destination: LicenseManager.websiteURL)
            Link("Report an Issue…", destination: AboutView.reportIssueURL)
            if let whatsNewVersion = appDelegate.whatsNewVersion {
                Divider()
                Button("What's New in \(whatsNewVersion)…") {
                    appDelegate.openWhatsNew()
                }
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, SPUUpdaterDelegate, ObservableObject {
    private static let whatsNewMenuItemTag = 180
    // Sparkle feed URL is defined in Info.plist (SUFeedURL) as the single source of truth.

    private var updaterController: SPUStandardUpdaterController?
    private var updaterStartupError: Error?
    private var updaterHasStarted = false
    
    private var monitoringObserver: NSObjectProtocol?
    private var controlCenterObserver: NSObjectProtocol?
    private var dockIconObserver: NSObjectProtocol?
    private var gameModeObserver: NSObjectProtocol?
    private var menuMetricsObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var settingsShortcutMonitor: Any?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var licenseNoticeWindow: NSWindow?
    private var gameModeDetector: GameModeDetector?
    private var monitorStateObserverToken: UUID?
    private var lastToggleTime: Date = .distantPast
    private let menuMetricsConsumerID = UUID()
    private var menuMetricsObserverToken: UUID?
    private var menuMetricsTimer: Timer?
    private var menuCurrentPingMs: Double?
    private var menuInterventionCount: Int?
    private var isStatusMenuOpen = false
    private let sessionCoordinator = ProtectedSessionCoordinator.shared
    private let protectionExperience = ProtectionExperienceCoordinator.shared
    private let settingsNavigation = SettingsNavigationModel()
    private var isTerminating = false
    /// Version whose release notes are on offer; nil once opened or when
    /// nothing is new. Published so the SwiftUI Help menu tracks it.
    @Published private(set) var whatsNewVersion: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Ping Warden launching...")

        sessionCoordinator.onSessionStateChanged = { [weak self] in
            self?.updateQuickActionMenuItems()
        }

        // Anonymous crash reporting defaults on only when no choice is saved.
        // The Settings privacy toggle is checked before SDK startup.
        CrashReporter.startIfEnabled()

        // Clear any cached Settings window state from prior builds that may have
        // injected fullSizeContentView or other window customizations via onAppear.
        // The SwiftUI Settings scene persists window frames under these keys.
        // Exclude our own AppKit settings window's autosave frame
        // ("PingWardenSettings") — deleting it every launch would throw away
        // the user's window size/position.
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.contains("NSWindow Frame") && key.contains("Settings") && !key.contains("PingWardenSettings") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Initialize monitoring before Sparkle so first-run UX can be gated on setup state.
        let monitor = PingWardenMonitor.shared

        // Licensing: grandfather existing installs (protection already
        // enabled and helper already approved) for 90 days, then enforce
        // the license gate.
        LicenseManager.shared.establishGrandfatheringIfNeeded(helperEnabled: monitor.isHelperRegistered)
        LicenseManager.shared.onReverificationSettled = { [weak self] in
            Task { @MainActor in
                await self?.protectionExperience.handleLicenseReverification()
                self?.presentDueLicenseNotice()
            }
        }
        LicenseManager.shared.startPeriodicReverification()
        LicenseManager.shared.reverifyAtLaunchIfNeeded()

        // The monitor only restores persisted protection when the gate
        // already held before grandfathering ran. A freshly grandfathered
        // install is restored by the launch reconcile below, which joins
        // any enable already in flight. A persisted intent whose
        // entitlement is gone is cleared here. Without an approved helper,
        // the intent waits for Finish Setup: enabling now would open Login
        // Items with no action from the person and stall for a minute.
        switch ProtectionExperiencePolicy.launchIntentAction(
            persistentProtectionEnabled: PingWardenPreferences.shared.isMonitoringEnabled,
            licenseAllowsProtection: LicenseManager.shared.canEnableProtection,
            helperRegistered: monitor.isHelperRegistered
        ) {
        case .none:
            break
        case .clearIntentForLicense:
            log.info("Clearing persisted protection intent: license entitlement is gone")
            protectionExperience.noteLaunchLicenseGate()
        case .waitForSetup:
            log.info("Saved protection intent is waiting for helper setup")
            protectionExperience.noteSetupIncomplete()
        }

        // Check on launch and while the app is in use. The persisted timestamp
        // prevents relaunches or missed weeks from producing repeated prompts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.presentDueLicenseNotice(allowBackground: true)
        }
#if DEBUG
        let debugWindowPrefix = "--show-window="
        let debugWindowTarget = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(debugWindowPrefix) })
            .map { String($0.dropFirst(debugWindowPrefix.count)) }
#else
        let debugWindowTarget: String? = nil
#endif

        // Initialize Sparkle updater and start explicitly so failures can be logged clearly.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController?.updater.clearFeedURLFromUserDefaults()
        // Defer only while the first-run introduction is still pending. Someone
        // who declines the helper and stays on the free dashboard is in a
        // supported state, and must still get scheduled update checks, security
        // fixes included. Keying this to helper registration alone left those
        // installs never checking for updates at all.
        if monitor.isHelperRegistered
            || !welcomePresentation.shouldPresentAutomatically(helperIsRegistered: monitor.isHelperRegistered) {
            _ = startUpdaterIfNeeded()
        } else {
            log.info("Deferring Sparkle updater start until the first-run introduction closes")
        }

        // Check for quarantine issues and help user if needed
        QuarantineHelper.showQuarantineHelpIfNeeded()

        // Set dock icon visibility based on preference
        updateDockIconVisibility()

        // Observe monitor state changes
        monitorStateObserverToken = monitor.addStateObserver { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.protectionExperience.refreshFromMonitor()
                self.updateMenuBarIcon()
                self.updateMenuItem()
                // If Sparkle was deferred during first-run setup, start it as
                // soon as the helper registration completes — otherwise
                // automatic update checks stay silently disabled all session.
                if PingWardenMonitor.shared.isHelperRegistered {
                    self.startUpdaterIfNeeded()
                }
            }
        }

        // Decide before the status menu is built whether this launch follows
        // an update; the What's New item only exists while there is one.
        prepareWhatsNewOffer()

        // Setup menu bar (unless Control Center mode is enabled AND widget is available)
        // Always check if widget is actually available before hiding menu bar
        let widgetAvailable = ControlCenterSupport.isAvailableForCurrentApp()
        if PingWardenPreferences.shared.controlCenterWidgetEnabled && !widgetAvailable {
            log.warning("Control Center widget enabled but not available (requires code signing). Resetting to menu bar.")
            PingWardenPreferences.shared.controlCenterWidgetEnabled = false
        }
        if !PingWardenPreferences.shared.controlCenterWidgetEnabled || !widgetAvailable {
            setupMenuBar()
        }

        // Helper setup can remain incomplete when someone only wants the
        // free dashboard. Show the optional introduction once, not every launch.
        if !monitor.isHelperRegistered {
            log.info("Helper setup is incomplete")
            if debugWindowTarget == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard self.welcomePresentation.shouldPresentAutomatically(
                        helperIsRegistered: PingWardenMonitor.shared.isHelperRegistered
                    ) else { return }
                    self.showWelcomeWindow()
                }
            }
        } else {
            log.info("Helper already registered")
            // Reconcile both directions at startup: start if the user wants
            // protection and it isn't running, but also stop if a widget/
            // Shortcuts toggle turned it off while the app wasn't running.
            handleMonitoringStateChange()

            // A registration can outlive the launchd job behind it, which
            // makes every request time out while the app looks set up and
            // skips the introduction. Only report here; rebuilding the
            // registration waits for the person to choose setup or Repair.
            monitor.confirmHelperResponds { [weak self] responds in
                Task { @MainActor in
                    guard let self, !responds else { return }
                    log.warning("Helper is registered but did not answer at launch")
                    self.protectionExperience.noteHelperNotResponding()
                    guard debugWindowTarget == nil,
                          self.welcomePresentation.shouldPresentAutomatically(helperIsRegistered: false) else { return }
                    self.showWelcomeWindow()
                }
            }
        }

#if DEBUG
        if let debugWindowTarget {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showDebugWindow(named: debugWindowTarget)
            }
        }
#endif

        // Setup Game Mode detector if enabled
        if PingWardenPreferences.shared.gameModeAutoDetect {
            setupGameModeDetector()
        }

        // Observe preference changes from widget (uses distributed notifications for cross-process)
        monitoringObserver = DistributedNotificationCenter.default().addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleExternalMonitoringStateChange()
            }
        }

        // Observe Control Center mode changes
        controlCenterObserver = NotificationCenter.default.addObserver(
            forName: .controlCenterModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleControlCenterModeChange()
            }
        }

        // Observe dock icon visibility changes
        dockIconObserver = NotificationCenter.default.addObserver(
            forName: .dockIconVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIconVisibility()
            }
        }

        // Observe Game Mode auto-detect changes
        gameModeObserver = NotificationCenter.default.addObserver(
            forName: .gameModeAutoDetectChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleGameModeAutoDetectChange()
            }
        }

        menuMetricsObserver = NotificationCenter.default.addObserver(
            forName: .menuDropdownMetricsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMenuMetricsPreferenceChange()
            }
        }

        handleMenuMetricsPreferenceChange()
        ensureApplicationMenuItems()
        installSettingsShortcutMonitor()
        installSettingsSectionObserver()

        // Observe all window close events so we can update dock icon visibility
        // when any foreground utility window closes.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIconVisibility()
            }
        }

        // Timers do not fire during sleep, and the helper can restart while
        // the Mac sleeps. Recheck the pause and reconcile protection on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.protectionExperience.handleSystemWake()
                self.updateMenuBarIcon()
                self.updateMenuItem()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Quit waits briefly for the helper to confirm the stop. Without the
    /// wait, AWDL stays down until the helper notices the closed connection,
    /// which can take up to a minute, and an enable still in flight could
    /// land after the app is gone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waiting = protectionExperience.prepareForTermination {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return waiting ? .terminateLater : .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Safety net for issue #28: when the menu bar icon is hidden (Control Center mode)
        // and the dock icon is off, re-launching the app is the only way back in.
        // Always open Settings when the app is re-opened with no visible windows.
        if !flag {
            openSettings()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ensureApplicationMenuItems()
        presentDueLicenseNotice()
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Ping Warden terminating...")
        isTerminating = true

        gameModeDetector?.stop()
        protectionExperience.finishForTermination()

        if let token = monitorStateObserverToken {
            PingWardenMonitor.shared.removeStateObserver(token)
            monitorStateObserverToken = nil
        }

        if let observer = monitoringObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = controlCenterObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = dockIconObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = gameModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = menuMetricsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let settingsShortcutMonitor {
            NSEvent.removeMonitor(settingsShortcutMonitor)
            self.settingsShortcutMonitor = nil
        }

        menuMetricsTimer?.invalidate()
        menuMetricsTimer = nil
        PingMonitor.shared.stop(consumerID: menuMetricsConsumerID)
        if let menuMetricsObserverToken {
            PingMonitor.shared.removeObserver(menuMetricsObserverToken)
            self.menuMetricsObserverToken = nil
        }
    }

    private func updateDockIconVisibility() {
        let settingsVisible = settingsWindow?.isVisible ?? false
        let aboutVisible = aboutWindow?.isVisible ?? false
        let welcomeVisible = welcomeWindow?.isVisible ?? false
        let licenseNoticeVisible = licenseNoticeWindow?.isVisible ?? false

        // Lockout invariant (H2): never hide the dock icon while Control
        // Center mode has the menu bar icon removed. Without this, unchecking
        // "Show Dock Icon" after enabling Control Center mode leaves no way
        // into the app except re-launching from Finder — and the state
        // persists across launches. (Checked against the preference, not
        // `statusItem == nil`, because this also runs at launch before
        // setupMenuBar() when statusItem is legitimately still nil.)
        if PingWardenPreferences.shared.controlCenterWidgetEnabled,
           !PingWardenPreferences.shared.showDockIcon {
            log.info("Menu bar icon is hidden (Control Center mode) — forcing dock icon on to prevent lockout")
            PingWardenPreferences.shared.showDockIcon = true
            // Deliberately fall through (no early return): at launch this
            // runs before the dockIconVisibilityChanged observer exists, so
            // relying on the setter's notification to re-enter would leave
            // the activation policy unset for the whole session.
        }

        if PingWardenPreferences.shared.showDockIcon || settingsVisible || aboutVisible || welcomeVisible || licenseNoticeVisible {
            NSApp.setActivationPolicy(.regular)
            ensureApplicationMenuItems()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Update dock icon visibility when a managed window closes.
        if window === settingsWindow || window === aboutWindow || window === welcomeWindow || window === licenseNoticeWindow {
            if window === settingsWindow {
                settingsWindow = nil
            }
            if window === aboutWindow {
                aboutWindow = nil
            }
            if window === welcomeWindow {
                welcomeWindow = nil
                // The introduction has been seen, so the first-run deferral is
                // over whether or not the helper was approved. Starting here
                // rather than when the window opens keeps Sparkle's own
                // permission prompt from stacking on top of the welcome.
                _ = startUpdaterIfNeeded()
            }
            if window === licenseNoticeWindow {
                licenseNoticeWindow = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.updateDockIconVisibility()
            }
        }
    }

    private func setupGameModeDetector() {
        gameModeDetector = GameModeDetector()
        gameModeDetector?.onGameModeChange = { [weak self] isActive in
            self?.handleGameModeStateChange(isActive: isActive)
        }
        gameModeDetector?.start()
        log.info("Game Mode detector started")
    }

    private func handleGameModeAutoDetectChange() {
        if PingWardenPreferences.shared.gameModeAutoDetect {
            // Stop existing detector first to prevent duplicates
            gameModeDetector?.stop()
            setupGameModeDetector()
        } else {
            gameModeDetector?.stop()
            gameModeDetector = nil
            log.info("Game Mode detector stopped")
        }
    }

    private func handleGameModeStateChange(isActive: Bool) {
        log.info("Game Mode state changed: \(isActive)")
        Task { @MainActor in
            await protectionExperience.setGameModeActive(isActive)
            updateMenuItem()
        }
    }

    // MARK: - Welcome Window

    private var welcomePresentation: WelcomePresentationState {
        WelcomePresentationState(defaults: PingWardenPreferences.shared.defaults)
    }

    private func showWelcomeWindow() {
        if welcomeWindow != nil { return }

        let experience = protectionExperience
        let welcomeView = WelcomeView { completion in
            // Repair covers first-time registration and a registration that
            // exists but never answers, and succeeds only on a helper reply.
            PingWardenMonitor.shared.repairHelperRegistration { registered in
                Task { @MainActor in
                    guard registered else {
                        completion(false)
                        return
                    }
                    // Setup is complete even without a license; only the
                    // protection toggle itself is gated. An unlicensed
                    // enable reports false and shows its message in the
                    // protectionExperience error surface.
                    _ = await experience.setPersistentProtection(true)
                    completion(true)
                }
            }
        } onOpenDashboard: {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            self.openDashboard()
        } onDismiss: {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            self.updateDockIconVisibility()
        } onOpenLicenseSettings: {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            self.settingsNavigation.selectedSection = .license
            self.openSettings()
        }

#if DEBUG
        var welcomeRootView = AnyView(welcomeView)
        if ProcessInfo.processInfo.arguments.contains("--welcome-large-text") {
            welcomeRootView = AnyView(
                welcomeRootView.environment(\.dynamicTypeSize, .accessibility5)
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--welcome-dark") {
            welcomeRootView = AnyView(welcomeRootView.preferredColorScheme(.dark))
        }
        let hostingController = NSHostingController(rootView: welcomeRootView)
#else
        let hostingController = NSHostingController(rootView: welcomeView)
#endif
#if DEBUG
        let initialSize = ProcessInfo.processInfo.arguments.contains("--welcome-min-size")
            ? NSSize(width: 480, height: 560)
            : WelcomeView.defaultSize
#else
        let initialSize = WelcomeView.defaultSize
#endif
        hostingController.view.frame = NSRect(origin: .zero, size: initialSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Welcome to Ping Warden"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        welcomeWindow = window

        // Show dock icon when welcome window opens
        NSApp.setActivationPolicy(.regular)

        window.makeKeyAndOrderFront(nil)
        welcomePresentation.markPresented()
        NSApp.activate(ignoringOtherApps: true)
        ensureApplicationMenuItems()
    }

    // MARK: - License Transition Notice

    private func presentDueLicenseNotice(allowBackground: Bool = false) {
        let license = LicenseManager.shared
        guard !isTerminating else { return }
        guard license.isGrandfathered else {
            if licenseNoticeWindow != nil { closeLicenseNoticeWindow() }
            return
        }
        guard licenseNoticeWindow == nil, welcomeWindow?.isVisible != true,
              !isStatusMenuOpen, !protectionExperience.gameModeActive,
              sessionCoordinator.phase == .idle, !license.isVerifying,
              license.storedLicenseKey == nil,
              allowBackground || NSApp.isActive else { return }
        let isReminder = license.transitionNoticeShown
        guard !isReminder || license.transitionReminderIsDue else { return }
        showLicenseTransitionNotice(isReminder: isReminder)
    }

    private func showLicenseTransitionNotice(isReminder: Bool) {
        guard licenseNoticeWindow == nil,
              LicenseManager.shared.isGrandfathered else { return }

        let view = LicenseTransitionNoticeView(
            isReminder: isReminder,
            onOpenLicenseSettings: { [weak self] in
                self?.closeLicenseNoticeWindow()
                self?.settingsNavigation.selectedSection = .license
                self?.openSettings()
            },
            onDismiss: { [weak self] in
                self?.closeLicenseNoticeWindow()
            }
        )

        let hostingController = NSHostingController(rootView: view)
        hostingController.view.frame = NSRect(origin: .zero, size: LicenseTransitionNoticeView.contentSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LicenseTransitionNoticeView.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = isReminder ? "Keep Ping Protection After Your Transition" : "Ping Warden License Transition"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        licenseNoticeWindow = window
        LicenseManager.shared.recordTransitionNoticePresented()

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ensureApplicationMenuItems()
    }

    private func closeLicenseNoticeWindow() {
        licenseNoticeWindow?.close()
        licenseNoticeWindow = nil
        updateDockIconVisibility()
    }

#if DEBUG
    private func showDebugWindow(named name: String) {
        switch name {
        case "dashboard":
            settingsNavigation.selectedSection = .dashboard
            openSettings()
        case "general":
            settingsNavigation.selectedSection = .general
            openSettings()
        case "automation":
            settingsNavigation.selectedSection = .automation
            openSettings()
        case "targets":
            settingsNavigation.selectedSection = .targets
            openSettings()
        case "license":
            settingsNavigation.selectedSection = .license
            openSettings()
        case "advanced":
            settingsNavigation.selectedSection = .advanced
            openSettings()
        case "about":
            showAbout()
        default:
            log.error("Unknown debug window target: \(name, privacy: .public)")
        }
    }
#endif

    // MARK: - Menu Bar

    private func setupMenuBar() {
        log.debug("Setting up menu bar")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard statusItem?.button != nil else {
            log.error("Failed to create status item button")
            return
        }

        updateMenuBarIcon()
        statusMenu = NSMenu()
        statusMenu?.delegate = self
        // Manual isEnabled control for the pause/resume items: with
        // autoenablesItems left on, AppKit re-enables any item whose target
        // responds to its action every time the menu opens, overriding the
        // assignments in updateQuickActionMenuItems().
        statusMenu?.autoenablesItems = false

        // State first, so the menu opens on what the app is doing.
        let statusMenuItem = NSMenuItem(title: "Status: Checking…", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        // A readout, not a command; enabled it looked clickable.
        statusMenuItem.isEnabled = false
        statusMenu?.addItem(statusMenuItem)

        let pingMenuItem = NSMenuItem(title: "Current Ping: --", action: nil, keyEquivalent: "")
        pingMenuItem.tag = 101
        pingMenuItem.isEnabled = false
        statusMenu?.addItem(pingMenuItem)

        let interventionsMenuItem = NSMenuItem(title: "Intervention Attempts: --", action: nil, keyEquivalent: "")
        interventionsMenuItem.tag = 102
        interventionsMenuItem.isEnabled = false
        statusMenu?.addItem(interventionsMenuItem)

        let showMetricsItem = NSMenuItem(
            title: "Show Live Metrics in Menu",
            action: #selector(toggleMenuDropdownMetrics),
            keyEquivalent: ""
        )
        showMetricsItem.tag = 160
        showMetricsItem.target = self
        // Open Dashboard keeps the chart symbol it shares with the sidebar.
        showMetricsItem.image = menuSymbol("speedometer")
        statusMenu?.addItem(showMetricsItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let dashboardItem = NSMenuItem(
            title: "Open Dashboard…",
            action: #selector(openDashboard),
            keyEquivalent: ""
        )
        dashboardItem.target = self
        dashboardItem.image = menuSymbol("chart.xyaxis.line")
        statusMenu?.addItem(dashboardItem)
        statusMenu?.addItem(NSMenuItem.separator())

        let initialPresentation = protectionExperience.menuPresentation()
        let toggleItem = NSMenuItem(
            title: initialPresentation.protectionTitle,
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.tag = 140
        toggleItem.image = protectionMenuImage()
        statusMenu?.addItem(toggleItem)

        let pauseItem = NSMenuItem(
            title: initialPresentation.pauseTitle ?? "Pause for 10 Minutes",
            action: #selector(toggleQuickPause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.image = menuSymbol("pause.circle")
        pauseItem.tag = 150
        statusMenu?.addItem(pauseItem)

        statusMenu?.addItem(NSMenuItem.separator())

        updateStatusMenuItem()
        updateMenuMetricsMenuItems()
        updateQuickActionMenuItems()
        handleMenuMetricsPreferenceChange()

        statusMenu?.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = menuSymbol("gearshape")
        statusMenu?.addItem(settingsItem)

        // Release notes for the version just installed, offered until opened.
        if let whatsNewVersion {
            let whatsNewItem = NSMenuItem(
                title: "What's New in \(whatsNewVersion)…",
                action: #selector(openWhatsNew),
                keyEquivalent: ""
            )
            whatsNewItem.target = self
            whatsNewItem.tag = Self.whatsNewMenuItemTag
            whatsNewItem.image = menuSymbol("sparkles")
            statusMenu?.addItem(whatsNewItem)
        }

        // Check for Updates (Sparkle)
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = menuSymbol("arrow.trianglehead.2.clockwise.rotate.90")
        statusMenu?.addItem(updateItem)

        let helpItem = NSMenuItem(title: "Help and Documentation", action: #selector(openDocumentation), keyEquivalent: "")
        helpItem.target = self
        helpItem.image = menuSymbol("questionmark.circle")
        statusMenu?.addItem(helpItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About Ping Warden",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = menuSymbol("info.circle")
        statusMenu?.addItem(aboutItem)

        // Shown only while unlicensed; the license pane carries the donation
        // conversion path, so the menu no longer needs a Donate item.
        let licenseItem = NSMenuItem(
            title: "Buy a License…",
            action: #selector(openLicenseSettings),
            keyEquivalent: ""
        )
        licenseItem.target = self
        licenseItem.tag = 170
        licenseItem.image = menuSymbol("checkmark.seal")
        licenseItem.isHidden = LicenseManager.shared.hasValidPaidLicense
        statusMenu?.addItem(licenseItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ping Warden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = menuSymbol("xmark.square")
        statusMenu?.addItem(quitItem)

        self.statusItem?.menu = statusMenu
    }

    private func menuSymbol(_ symbolName: String, accessibilityDescription: String? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    private func protectionMenuImage() -> NSImage? {
        let isMonitoring = PingWardenMonitor.shared.isMonitoringActive
        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let description = isMonitoring ? "Turn Off Ping Protection" : "Turn On Ping Protection"
        return menuSymbol(symbolName, accessibilityDescription: description)
    }

    private func removeMenuBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            statusMenu = nil
        }
        stopMenuMetricsMonitoring()
    }

    @objc func openSettings() {
        log.info("openSettings called")
        NSApp.setActivationPolicy(.regular)
        showSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        ensureApplicationMenuItems()
    }

    @objc private func openDashboard() {
        settingsNavigation.selectedSection = .dashboard
        openSettings()
        growSettingsWindowForDashboard()
    }

    /// A frame restored from a short settings session can hide the chart,
    /// so grow to the default height when the dashboard is what was asked
    /// for. The rest of the dashboard scrolls.
    private func growSettingsWindowForDashboard() {
        guard let window = settingsWindow, let screen = window.screen ?? NSScreen.main else { return }
        let target: CGFloat = 780
        guard window.frame.height < target else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.height = min(target, visible.height)
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        window.setFrame(frame, display: true, animate: true)
    }

    @objc func openAbout() {
        showAbout()
    }

    /// The dashboard's target summary asks for the Targets pane by name; the
    /// dashboard view has no handle on the navigation model, so it posts.
    private func installSettingsSectionObserver() {
        NotificationCenter.default.addObserver(
            forName: .pingWardenOpenSettingsSection,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?["section"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      let section = SettingsSection(rawValue: raw) else { return }
                self.settingsNavigation.selectedSection = section
                self.openSettings()
            }
        }
    }

    private func installSettingsShortcutMonitor() {
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers == "," else {
                return event
            }

            self?.openSettings()
            return nil
        }
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            updateDockIconVisibility()
            return
        }

        let settingsView = SettingsView(
            navigationModel: settingsNavigation,
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
            }
        )
        let hostingController = NSHostingController(rootView: settingsView)
        // The window owns its size: minSize below and the root view's
        // minimum frame bound it. With the default .standardBounds the
        // controller re-measured the whole layout on every dashboard sample.
        hostingController.sizingOptions = []
        // Fits a laptop screen; the dashboard scrolls. A frame the person
        // saved under the autosave name below still wins.
        let defaultSize = NSSize(width: 900, height: 780)
#if DEBUG
        let usesDebugMinimumSize = ProcessInfo.processInfo.arguments.contains("--settings-min-size")
        let initialSize = usesDebugMinimumSize
            ? NSSize(width: 760, height: 520)
            : defaultSize
#else
        let usesDebugMinimumSize = false
        let initialSize = defaultSize
#endif
        hostingController.view.frame = NSRect(origin: .zero, size: initialSize)

        if #available(macOS 14.0, *) {
            hostingController.sceneBridgingOptions = .all
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.title = "Settings"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = false
        window.toolbar?.showsBaselineSeparator = false
        // Center first, then attach the autosave name: setFrameAutosaveName
        // restores any saved frame, so the restored position must not be
        // clobbered by a subsequent center().
        window.center()
        if !usesDebugMinimumSize {
            window.setFrameAutosaveName("PingWardenSettings")
        }

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        updateDockIconVisibility()
    }

    @objc private func showAbout() {
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            ensureApplicationMenuItems()
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Ping Warden"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 380, height: 420)
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        aboutWindow = window
        
        // Show dock icon when about window opens
        NSApp.setActivationPolicy(.regular)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ensureApplicationMenuItems()
    }

    @objc private func openDocumentation() {
        NSWorkspace.shared.open(LicenseManager.documentationURL)
    }

    // MARK: - What's New

    /// Sparkle shows release notes only before an update installs, so someone
    /// who clicked Install without reading has nothing in the app afterwards
    /// that says what changed. Decide once per launch whether to offer them.
    private func prepareWhatsNewOffer() {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            log.warning("Bundle has no CFBundleShortVersionString; skipping What's New")
            return
        }
        let preferences = PingWardenPreferences.shared
        guard let lastSeenVersion = preferences.lastSeenWhatsNewVersion else {
            // Fresh install: nothing to catch up on. Record the baseline so
            // the next update is the first one offered.
            preferences.lastSeenWhatsNewVersion = currentVersion
            return
        }
        guard WhatsNewPolicy.shouldOffer(lastSeenVersion: lastSeenVersion, currentVersion: currentVersion) else {
            return
        }
        log.info("Offering What's New for \(currentVersion, privacy: .public); last seen \(lastSeenVersion, privacy: .public)")
        whatsNewVersion = currentVersion
    }

    /// Opens the release notes for the running version and retires the offer
    /// from both menus. The menu item is the whole surface: no window, no alert.
    @objc func openWhatsNew() {
        guard let version = whatsNewVersion else { return }
        if let url = WhatsNewPolicy.releaseNotesURL(for: version) {
            NSWorkspace.shared.open(url)
        } else {
            log.error("No release notes URL for version \(version, privacy: .public)")
        }
        PingWardenPreferences.shared.lastSeenWhatsNewVersion = version
        whatsNewVersion = nil
        if let menu = statusMenu,
           let item = menu.items.first(where: { $0.tag == Self.whatsNewMenuItemTag }) {
            menu.removeItem(item)
        }
    }

    @objc private func openLicenseSettings() {
        settingsNavigation.selectedSection = .license
        openSettings()
    }

    @objc func checkForUpdates() {
        guard startUpdaterIfNeeded() else {
            presentUpdaterStartFailureAlert()
            return
        }

        if let activeFeedURL = updaterController?.updater.feedURL?.absoluteString {
            log.info("Checking Sparkle updates from feed: \(activeFeedURL, privacy: .public)")
        }
        
        updaterController?.updater.checkForUpdates()
    }

    @discardableResult
    private func startUpdaterIfNeeded() -> Bool {
        guard let updater = updaterController?.updater else {
            return false
        }

        if updaterHasStarted {
            return true
        }

        do {
            try updater.start()
            updaterHasStarted = true
            updaterStartupError = nil
            return true
        } catch {
            updaterStartupError = error
            log.error("Sparkle updater failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func ensureApplicationMenuItems() {
        guard NSApp.activationPolicy() == .regular,
              let mainMenu = NSApp.mainMenu,
              let appMenu = mainMenu.items.first?.submenu else {
            return
        }

        if let aboutItem = appMenu.items.first(where: { $0.title.hasPrefix("About ") }) {
            aboutItem.target = self
            aboutItem.action = #selector(showAbout)
        }

        // Check for Updates is declared as a SwiftUI command, which survives
        // the menu rebuilds that removed an item inserted here.
        if let settingsItem = appMenu.items.first(where: { $0.keyEquivalent == "," || $0.title == "Settings…" }) {
            settingsItem.title = "Settings…"
            settingsItem.target = self
            settingsItem.action = #selector(openSettings)
            settingsItem.keyEquivalent = ","
        } else if let aboutIndex = appMenu.items.firstIndex(where: { $0.title.hasPrefix("About ") }) {
            let settingsItem = NSMenuItem(
                title: "Settings…",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
            settingsItem.target = self
            appMenu.insertItem(settingsItem, at: aboutIndex + 1)
        }
    }

    private func presentUpdaterStartFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "Unable to Check for Updates"
        let errorText: String
        if let startupError = updaterStartupError as NSError? {
            errorText = "\(startupError.domain) \(startupError.code): \(startupError.localizedDescription)"
        } else {
            errorText = "The updater did not provide an error message."
        }
        alert.informativeText = "Ping Warden could not start its updater. You can retry, open the latest release in your browser, or copy the error for troubleshooting.\n\n\(errorText)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Download Latest Release")
        alert.addButton(withTitle: "Copy Error")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if startUpdaterIfNeeded() {
                updaterController?.updater.checkForUpdates()
            }
        case .alertSecondButtonReturn:
            if let releasesURL = URL(string: "https://github.com/oliverames/ping-warden/releases/latest") {
                NSWorkspace.shared.open(releasesURL)
            }
        case .alertThirdButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(errorText, forType: .string)
        default:
            break
        }
    }

    /// Sparkle calls this on every update check. Returning nil falls back to
    /// the `SUFeedURL` in Info.plist (stable channel). Returning the beta URL
    /// makes Sparkle pull `appcast-beta.xml` for opted-in users. The beta
    /// appcast is on the same gh-pages branch, signed with the same EdDSA
    /// key, just a separate XML file.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        guard PingWardenPreferences.shared.betaChannelEnabled else {
            return nil
        }
        return "https://oliverames.github.io/ping-warden/appcast-beta.xml"
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        log.error("Sparkle update cycle aborted: [\(nsError.domain, privacy: .public):\(nsError.code)] \(nsError.localizedDescription, privacy: .public)")
    }
    
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            let nsError = error as NSError
            log.error("Sparkle update cycle finished with error for \(String(describing: updateCheck), privacy: .public): [\(nsError.domain, privacy: .public):\(nsError.code)] \(nsError.localizedDescription, privacy: .public)")
        } else {
            log.info("Sparkle update cycle finished successfully for \(String(describing: updateCheck), privacy: .public)")
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isMonitoring = PingWardenMonitor.shared.isMonitoringActive
        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let accessibilityDesc = isMonitoring ? "Ping Warden: Protected" : "Ping Warden: Not Protected"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDesc)
        image?.isTemplate = true

        button.image = image
        button.toolTip = isMonitoring ? "Ping Protection: Active" : "Ping Protection: Inactive"

        // Accessibility for VoiceOver
        button.setAccessibilityLabel(accessibilityDesc)
        button.setAccessibilityRole(.button)
    }

    private func updateMenuItem() {
        guard let menu = statusMenu else { return }

        let presentation = protectionExperience.menuPresentation()
        if let toggleItem = menu.items.first(where: { $0.tag == 140 }) {
            toggleItem.title = presentation.protectionTitle
            toggleItem.image = protectionMenuImage()
            toggleItem.isEnabled = presentation.protectionActionEnabled
        }

        updateStatusMenuItem()
        updateMenuMetricsMenuItems()
        updateQuickActionMenuItems()
    }

    private func updateMenuMetricsMenuItems() {
        guard let menu = statusMenu else { return }

        let showMetrics = PingWardenPreferences.shared.showMenuDropdownMetrics

        if let toggleItem = menu.items.first(where: { $0.tag == 160 }) {
            toggleItem.state = showMetrics ? .on : .off
        }

        if let pingItem = menu.items.first(where: { $0.tag == 101 }) {
            pingItem.isHidden = !showMetrics
            if let ping = menuCurrentPingMs {
                pingItem.title = String(format: "Current Ping: %.0f ms", ping)
            } else {
                pingItem.title = "Current Ping: --"
            }
        }

        if let interventionsItem = menu.items.first(where: { $0.tag == 102 }) {
            interventionsItem.isHidden = !showMetrics
            if let count = menuInterventionCount {
                interventionsItem.title = "Intervention Attempts: \(count)"
            } else {
                interventionsItem.title = "Intervention Attempts: --"
            }
        }
    }

    private func updateQuickActionMenuItems() {
        guard let menu = statusMenu else { return }

        let presentation = protectionExperience.menuPresentation()
        if let pauseItem = menu.items.first(where: { $0.tag == 150 }) {
            pauseItem.isHidden = presentation.pauseTitle == nil
            pauseItem.title = presentation.pauseTitle ?? "Pause for 10 Minutes"
            pauseItem.isEnabled = presentation.pauseActionEnabled
            pauseItem.image = menuSymbol(
                presentation.pauseTitle?.hasPrefix("Resume") == true
                    ? "play.circle"
                    : "pause.circle"
            )
        }

    }

    private func updateStatusMenuItem() {
        guard let menu = statusMenu,
              let statusItem = menu.items.first(where: { $0.tag == 100 }) else { return }

        statusItem.title = protectionExperience.menuPresentation().statusTitle
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.tag == 170 })?.isHidden = LicenseManager.shared.hasValidPaidLicense
        guard menu === statusMenu else { return }
        isStatusMenuOpen = true
        syncMenuMetricsTargetIfNeeded()
        updateMenuItem()
        refreshMenuInterventionCount()
        // Live dropdown metrics only run while the menu can actually show
        // them; opening starts the probe and intervention polling and
        // closing tears it down again.
        if PingWardenPreferences.shared.showMenuDropdownMetrics {
            startMenuMetricsMonitoring()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isStatusMenuOpen = false
        DispatchQueue.main.async { [weak self] in
            self?.presentDueLicenseNotice(allowBackground: true)
        }
        if PingWardenPreferences.shared.showMenuDropdownMetrics {
            stopMenuMetricsMonitoring()
        }
    }

    @objc private func toggleMonitoring() {
        // Debounce rapid toggles to prevent race conditions
        let now = Date()
        guard now.timeIntervalSince(lastToggleTime) > 0.5 else {
            log.debug("Toggle debounced - too soon since last toggle")
            return
        }
        lastToggleTime = now

        // The item's title comes from the same decision, so what it says is
        // what it does.
        let action = protectionExperience.toggleAction()
        guard action != .finishSetup else {
            showWelcomeWindow()
            return
        }

        let shouldEnable = action == .turnOn
        Task {
            let succeeded = await protectionExperience.setPersistentProtection(shouldEnable)
            updateMenuItem()
            guard !succeeded else { return }
            if shouldEnable,
               protectionExperience.lastError?.localizedCaseInsensitiveContains("license") == true {
                presentLicenseDeniedAlert()
            } else {
                presentMenuActionFailure(
                    title: shouldEnable
                        ? "Ping Protection Could Not Turn On"
                        : "Ping Protection Could Not Turn Off"
                )
            }
        }
    }

    /// The menu has no place to show `lastError`, so an action started from
    /// it reports a failure in one alert. Automated paths never do this;
    /// their errors wait in the Dashboard and Settings.
    private func presentMenuActionFailure(title: String) {
        guard let message = protectionExperience.lastError else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentLicenseDeniedAlert() {
        // The coordinator's message already says the same thing, so the
        // alert states it once rather than appending purchase directions.
        let alert = NSAlert()
        alert.messageText = "Ping Protection Requires a License"
        alert.informativeText = LicenseCopy.required(
            transitionEnded: LicenseManager.shared.grandfatherWindowExpired
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Buy a License…")
        alert.addButton(withTitle: "Enter License Key…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(LicenseManager.purchaseURL)
        case .alertSecondButtonReturn:
            openLicenseSettings()
        default:
            break
        }
    }

    @objc private func toggleMenuDropdownMetrics() {
        PingWardenPreferences.shared.showMenuDropdownMetrics.toggle()
    }

    @objc private func toggleQuickPause() {
        Task {
            if protectionExperience.pauseUntil != nil {
                await protectionExperience.resumeProtection()
                updateMenuItem()
            } else {
                await protectionExperience.pauseForTenMinutes()
                updateMenuItem()
                if protectionExperience.pauseUntil == nil, protectionExperience.lastError != nil {
                    presentMenuActionFailure(title: "Ping Protection Could Not Pause")
                }
            }
        }
    }

    private func handleMenuMetricsPreferenceChange() {
        guard statusItem != nil else {
            stopMenuMetricsMonitoring()
            return
        }

        if PingWardenPreferences.shared.showMenuDropdownMetrics, isStatusMenuOpen {
            startMenuMetricsMonitoring()
        } else {
            stopMenuMetricsMonitoring()
        }
        updateMenuMetricsMenuItems()
    }

    private func startMenuMetricsMonitoring() {
        let target = menuMetricsTarget()

        if menuMetricsObserverToken == nil {
            menuMetricsObserverToken = PingMonitor.shared.addObserver { [weak self] snapshot in
                guard let self else { return }
                let result = snapshot.latestResult
                self.menuCurrentPingMs = result.success ? result.latencyMs : nil
                self.updateMenuMetricsMenuItems()
            }
        }
        PingMonitor.shared.start(
            consumerID: menuMetricsConsumerID,
            server: target.host,
            port: target.port,
            interval: 2,
            priority: 10
        )

        refreshMenuInterventionCount()

        if menuMetricsTimer == nil {
            menuMetricsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.syncMenuMetricsTargetIfNeeded()
                    self?.refreshMenuInterventionCount()
                }
            }
            if let menuMetricsTimer {
                RunLoop.main.add(menuMetricsTimer, forMode: .common)
            }
        }
    }

    private func stopMenuMetricsMonitoring() {
        menuMetricsTimer?.invalidate()
        menuMetricsTimer = nil
        PingMonitor.shared.stop(consumerID: menuMetricsConsumerID)
        if let menuMetricsObserverToken {
            PingMonitor.shared.removeObserver(menuMetricsObserverToken)
            self.menuMetricsObserverToken = nil
        }
        menuCurrentPingMs = nil
        menuInterventionCount = nil
    }

    private func syncMenuMetricsTargetIfNeeded() {
        guard PingWardenPreferences.shared.showMenuDropdownMetrics else { return }

        let target = menuMetricsTarget()
        PingMonitor.shared.start(
            consumerID: menuMetricsConsumerID,
            server: target.host,
            port: target.port,
            interval: 2,
            priority: 10
        )
    }

    private func refreshMenuInterventionCount() {
        guard PingWardenPreferences.shared.showMenuDropdownMetrics else { return }

        PingWardenMonitor.shared.getInterventionCount { [weak self] count in
            Task { @MainActor in
                guard let self, let count else { return }
                self.menuInterventionCount = count
                self.updateMenuMetricsMenuItems()
            }
        }
    }

    private func menuMetricsTarget() -> (host: String, port: UInt16) {
        let defaultTarget = ("8.8.8.8", UInt16(53))
        guard let rawTargetID = UserDefaults.standard.string(forKey: "DashboardSelectedPingTargetID"),
              let separatorIndex = rawTargetID.lastIndex(of: ":") else {
            return defaultTarget
        }

        let hostPart = String(rawTargetID[..<separatorIndex])
        let portPart = String(rawTargetID[rawTargetID.index(after: separatorIndex)...])
        guard !hostPart.isEmpty, let port = UInt16(portPart) else {
            return defaultTarget
        }

        return (hostPart, port)
    }

    private func handleMonitoringStateChange() {
        let shouldMonitor = PingWardenPreferences.shared.isMonitoringEnabled
        Task { @MainActor in
            // A persisted pause restored at launch outranks the stored
            // protection intent until it expires; resumeProtection enables
            // blocking when the pause timer fires.
            if !protectionExperience.isPauseActive {
                _ = await protectionExperience.setPersistentProtection(shouldMonitor)
            }
            updateMenuBarIcon()
            updateMenuItem()
        }
    }

    private func handleExternalMonitoringStateChange() {
        let effectiveState = PingWardenPreferences.shared.effectiveMonitoringEnabled
        Task { @MainActor in
            await protectionExperience.handleExternallyAppliedProtectionState(effectiveState)
            updateMenuBarIcon()
            updateMenuItem()
        }
    }

    private func handleControlCenterModeChange() {
        // Control Center widgets require proper code signing to work
        // For unsigned/ad-hoc signed apps, always keep menu bar visible
        let isProperlySignedForControlCenter = ControlCenterSupport.isAvailableForCurrentApp()

        if PingWardenPreferences.shared.controlCenterWidgetEnabled && isProperlySignedForControlCenter {
            // Safety invariant (H2): never remove the menu bar if the dock icon is also hidden,
            // as this would leave the user with no way to access the app.
            if !PingWardenPreferences.shared.showDockIcon {
                log.info("Control Center mode enabled — forcing dock icon on to prevent lockout")
                PingWardenPreferences.shared.showDockIcon = true
            }
            removeMenuBar()
        } else {
            // Reset preference if widget isn't available
            if PingWardenPreferences.shared.controlCenterWidgetEnabled && !isProperlySignedForControlCenter {
                log.warning("Control Center widget not available (requires code signing). Reverting to menu bar.")
                PingWardenPreferences.shared.controlCenterWidgetEnabled = false
            }
            if statusItem == nil {
                setupMenuBar()
            }
        }
    }

}

// MARK: - License Transition Notice View

/// Introductory notice and deadline reminders share the purchase and activation flow.
struct LicenseTransitionNoticeView: View {
    static let contentSize = CGSize(width: 480, height: 560)

    let isReminder: Bool
    @ObservedObject private var license = LicenseManager.shared
    private var daysRemaining: Int? { license.grandfatherDaysRemaining }
    let onOpenLicenseSettings: () -> Void
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: heroIconSize, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    Text(isReminder ? "Keep Ping Protection After Your Transition" : "Ping Warden Is Moving to a License")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 8) {
                        if let daysRemaining {
                            Text("Your transition has \(daysRemaining) \(daysRemaining == 1 ? "day" : "days") remaining.")
                                .fontWeight(.semibold)
                            Text("Buy and activate a one-time $15 license before the transition ends to keep Ping Protection available. Until then, protection continues to work on this Mac.")
                        }
                        Text(LicenseReminderPolicy.followUpMessage(daysRemaining: daysRemaining))
                        Text("Everything else in Ping Warden stays free, and the source code remains open under the MIT License.")
                    }
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)

                VStack(spacing: 8) {
                    Text("Already supported Ping Warden?")
                        .font(.headline)
                    Text("If you donated through the Buy Me a Coffee link before version 4, email \(LicenseManager.donationConversionEmail) and that support will be honored as a full license.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Email \(LicenseManager.donationConversionEmail)") {
                        NSWorkspace.shared.open(URL(string: "mailto:\(LicenseManager.donationConversionEmail)?subject=Ping%20Warden%20license%20from%20donation")!)
                    }
                    .controlSize(.small)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 20)
                .padding(.horizontal, 24)

                VStack(spacing: 10) {
                    Button {
                        onDismiss()
                        NSWorkspace.shared.open(LicenseManager.purchaseURL)
                    } label: {
                        Text("Buy Ping Protection · $15").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Button {
                        onOpenLicenseSettings()
                    } label: {
                        Text("Enter a License Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Continue Using Ping Warden")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 24)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Settings View

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedSection: SettingsSection = .general
}

struct SettingsView: View {
    let onCheckForUpdates: () -> Void
    @ObservedObject var navigationModel: SettingsNavigationModel

    init(
        navigationModel: SettingsNavigationModel,
        onCheckForUpdates: @escaping () -> Void = {}
    ) {
        self.navigationModel = navigationModel
        self.onCheckForUpdates = onCheckForUpdates
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationModel.selectedSection) {
                Section {
                    Label(SettingsSection.dashboard.rawValue, systemImage: SettingsSection.dashboard.icon)
                        .tag(SettingsSection.dashboard)
                }
                Section("Settings") {
                    ForEach(SettingsSection.allCases.filter { $0 != .dashboard }) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            SettingsContentView(
                section: navigationModel.selectedSection,
                onCheckForUpdates: onCheckForUpdates
            )
            .navigationTitle(navigationModel.selectedSection.rawValue)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .settingsToolbarMaterial()
        .frame(minWidth: 760, minHeight: 520)
    }
}

private extension View {
    @ViewBuilder
    func settingsToolbarMaterial() -> some View {
        if #available(macOS 15.0, *) {
            self
                .toolbarBackground(.bar, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self
                .toolbarBackground(.bar, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
    }

    @ViewBuilder
    func settingsScrollEdgeTreatment() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case general = "General"
    case license = "License"
    case targets = "Targets"
    case automation = "Automation"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .general: return "gearshape"
        case .license: return "checkmark.seal"
        case .targets: return "server.rack"
        case .automation: return "sparkles"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsContentView: View {
    let section: SettingsSection
    let onCheckForUpdates: () -> Void

    var body: some View {
        Group {
            switch section {
            case .dashboard:
                dashboardContent
            case .general:
                GeneralSettingsContent(onCheckForUpdates: onCheckForUpdates)
            case .license:
                LicenseSettingsContent()
            case .targets:
                TargetsSettingsContent()
                    .settingsScrollEdgeTreatment()
            case .automation:
                AutomationSettingsContent()
            case .advanced:
                AdvancedSettingsContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dashboardContent: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DashboardSettingsContent()
                }

                Spacer(minLength: 20)
            }
            .scrollContentBackground(.hidden)
            .settingsScrollEdgeTreatment()
        }
        // No explicit .background here: on macOS 26 the Settings scene
        // already renders with the system Liquid Glass material, and an
        // opaque windowBackgroundColor on top would obscure it. On
        // macOS 13-25 the inherited scene background continues to look
        // correct without us setting one explicitly.
    }
}

// MARK: - Settings Components

private let settingsLog = Logger(subsystem: "com.amesvt.pingwarden", category: "Settings")

/// Small pill badge ("Unavailable", "Needs Permission", etc.) with WCAG AA contrast.
/// White text on a darker-tinted fill passes >=4.5:1 in both light and dark
/// mode without depending on the parent background. Replaces the previous
/// `.opacity(0.2)` pattern which scored 1.71:1 in light mode (text was nearly
/// invisible to low-vision users).
struct StatusBadge: View {
    enum Tint {
        case unavailable
        case informational
    }

    let text: String
    let tint: Tint

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fillColor, in: Capsule())
            .accessibilityLabel(voiceOverLabel)
    }

    private var fillColor: Color {
        switch tint {
        case .unavailable: return Color(red: 0.40, green: 0.40, blue: 0.40)
        case .informational: return Color(red: 0.24, green: 0.42, blue: 0.62)
        }
    }

    private var voiceOverLabel: String {
        switch tint {
        case .unavailable, .informational: return "\(text)"
        }
    }
}

// MARK: - General Settings Content

struct GeneralSettingsContent: View {
    let onCheckForUpdates: () -> Void
    @StateObject private var monitorState = MonitoringStateStore()
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDockIcon = PingWardenPreferences.shared.showDockIcon
    @State private var showMenuDropdownMetrics = PingWardenPreferences.shared.showMenuDropdownMetrics
    @State private var settingsErrorMessage: String?
    @State private var isFinishingSetup = false

    init(onCheckForUpdates: @escaping () -> Void = {}) {
        self.onCheckForUpdates = onCheckForUpdates
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ping Warden")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 16)

                    Button("Check for Updates…", action: onCheckForUpdates)
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }

            Section("Protection") {
                if monitorState.isHelperRegistered {
                    Toggle(isOn: Binding(
                        get: { PingWardenPreferences.shared.isMonitoringEnabled },
                        set: { newValue in
                            Task {
                                await protectionExperience.setPersistentProtection(newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep Ping Protection On")
                            Text("Keep protection active outside Latency Sessions and Game Mode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(protectionExperience.isBusy)
                    .accessibilityLabel("Keep Ping Protection On")
                    .accessibilityHint("Controls ongoing protection outside temporary latency sessions and Game Mode")
                } else {
                    LabeledContent {
                        Button {
                            finishSetup()
                        } label: {
                            if setupInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Finish Setup…")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(setupInProgress)
                        .accessibilityLabel("Finish Setup…")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ping Protection")
                            Text("Approve the helper to finish setup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = protectionExperience.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        if error.localizedCaseInsensitiveContains("license") {
                            Button("Buy a License…") {
                                NSWorkspace.shared.open(LicenseManager.purchaseURL)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Status")
                .accessibilityValue(statusText)

                if monitorState.isMonitoring && monitorState.interventionCount > 0 {
                    LabeledContent("Intervention Attempts") {
                        HStack(spacing: 8) {
                            Text("\(monitorState.interventionCount)")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                PingWardenMonitor.shared.resetInterventionCount { success in
                                    Task { @MainActor in
                                        if success {
                                            monitorState.refresh()
                                        } else {
                                            settingsErrorMessage = "The helper could not reset the intervention counter. Open Settings → Advanced, click Repair, and try again."
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Reset intervention attempt counter")
                            .help("Reset counter")
                        }
                    }
                }
            }

            Section("App") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                        } catch {
                            settingsLog.error("Failed to update login item: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            settingsErrorMessage = "Launch at Login could not be changed. \(error.localizedDescription)"
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Start Ping Warden when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $showDockIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Dock Icon")
                        Text("Display app icon in the Dock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChangeCompat(of: showDockIcon) { newValue in
                    PingWardenPreferences.shared.showDockIcon = newValue
                }

                Toggle(isOn: $showMenuDropdownMetrics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Live Metrics in Menu")
                            Text("Show current ping and intervention attempts in the menu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChangeCompat(of: showMenuDropdownMetrics) { newValue in
                    PingWardenPreferences.shared.showMenuDropdownMetrics = newValue
                }
            }

            Section {
                Label("No Password Prompts", systemImage: "checkmark.shield")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } header: {
                Text("How It Works")
            } footer: {
                Text("AWDL (Apple Wireless Direct Link) powers AirDrop, AirPlay, and Handoff. Its radio activity can interrupt latency-sensitive traffic. Ping Warden uses a background helper to block AWDL while protection is active. The helper requires one system approval and runs on demand.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeTreatment()
        .onAppear {
            monitorState.startObserving()
        }
        .onDisappear {
            monitorState.stopObserving()
        }
        .alert(
            "Setting Could Not Be Changed",
            isPresented: Binding(
                get: { settingsErrorMessage != nil },
                set: { if !$0 { settingsErrorMessage = nil } }
            )
        ) {
            Button("OK") { settingsErrorMessage = nil }
        } message: {
            Text(settingsErrorMessage ?? "Try again.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Covers a repair started from Advanced or the welcome window too, so
    /// a second one cannot unregister the helper the first just rebuilt.
    private var setupInProgress: Bool {
        isFinishingSetup || protectionExperience.isRepairingHelper
    }

    private func finishSetup() {
        guard !setupInProgress else { return }
        isFinishingSetup = true
        PingWardenMonitor.shared.repairHelperRegistration(presentsErrors: false) { success in
            Task { @MainActor in
                guard success else {
                    isFinishingSetup = false
                    settingsErrorMessage = PingWardenMonitor.shared.lastSetupFailureMessage
                        ?? (PingWardenMonitor.shared.isHelperRegistered
                            ? "The helper was approved but is not responding. Restart your Mac, then open Settings → Advanced and click Repair."
                            : "Ping Warden is still waiting for approval in \(SystemSettingsCopy.loginItemsPath).")
                    return
                }
                let enabled = await protectionExperience.setPersistentProtection(true)
                isFinishingSetup = false
                if !enabled {
                    settingsErrorMessage = protectionExperience.lastError
                        ?? "The helper was approved, but Ping Protection could not turn on. Open Settings → Advanced and click Repair."
                }
            }
        }
    }

    private var statusColor: Color {
        if !monitorState.isHelperRegistered { return .gray }
        return monitorState.isMonitoring ? .green : .orange
    }

    private var statusText: String {
        if !monitorState.isHelperRegistered { return "Not Set Up" }
        return monitorState.isMonitoring ? "Protected" : "Not Protected"
    }
}

// MARK: - License Settings Content

struct LicenseSettingsContent: View {
    @ObservedObject private var license = LicenseManager.shared
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @State private var keyField = ""
    @State private var licenseMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: license.canEnableProtection ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(license.canEnableProtection ? .green : .secondary)
                            .accessibilityHidden(true)
                        Text(license.hasValidPaidLicense ? "Licensed" : (license.isGrandfathered ? "Free Transition" : "Unlicensed"))
                            .font(.headline)
                    }

                    Text(statusCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Ping Protection License")
            } footer: {
                Text("Ping Warden is open source, and everything except enabling Ping Protection is free. A license keeps Ping Protection available and supports development.")
            }

            if license.isGrandfathered {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let days = license.grandfatherDaysRemaining {
                            Text("Ping Warden is moving to a paid model for Ping Protection. As an existing user, this Mac keeps full Ping Protection for \(days) more days, free and with no action needed.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Ping Warden is moving to a paid model for Ping Protection. As an existing user, this Mac keeps full Ping Protection during a 90-day transition, free and with no action needed.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("After the transition ends, a $15 one-time license keeps Ping Protection available. Everything else in the app stays free, and the source remains open under MIT.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If you donated through the Buy Me a Coffee link before version 4, thank you. Email \(LicenseManager.donationConversionEmail) and that support will be honored as a full license.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Email \(LicenseManager.donationConversionEmail)") {
                            NSWorkspace.shared.open(URL(string: "mailto:\(LicenseManager.donationConversionEmail)?subject=Ping%20Warden%20license%20from%20donation")!)
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Text("Transition Period")
                } footer: {
                    Text("Enter a license key below any time during the transition. Nothing changes until it ends.")
                }

                keyEntrySection
            } else if !license.canEnableProtection {
                keyEntrySection

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you donated through the Buy Me a Coffee link before version 4, thank you. Email \(LicenseManager.donationConversionEmail) and that support will be honored as a full license.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Email \(LicenseManager.donationConversionEmail)") {
                            NSWorkspace.shared.open(URL(string: "mailto:\(LicenseManager.donationConversionEmail)?subject=Ping%20Warden%20license%20from%20donation")!)
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Text("Donated Before?")
                }
            }

            if let error = protectionExperience.lastError,
               error.contains("license") {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Buy a License…") {
                        NSWorkspace.shared.open(LicenseManager.purchaseURL)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusCaption: String {
        // The entry section disappears once a key verifies, so the status
        // section is where that confirmation stays visible. LicenseManager
        // does not expose the verification date, so none is shown.
        if license.hasValidPaidLicense {
            return "License verified. Ping Protection is available on this Mac."
        }
        if license.isGrandfathered {
            return "Full Ping Protection continues free during the transition period."
        }
        if license.canEnableProtection {
            return "Ping Protection is available on this Mac."
        }
        return "Enter a license key to enable Ping Protection."
    }

    /// Plain text rather than a secure field, so a paste that picked up too
    /// much or too little is visible. The key is still stored in the keychain.
    private var keyEntrySection: some View {
        Section("Enter License Key") {
            // The label sits above a full-width field: beside it, a grouped
            // form right-aligns the field's text, and a key reads from its start.
            VStack(alignment: .leading, spacing: 6) {
                Text("License Key")
                    .accessibilityHidden(true)
                TextField("License Key", text: $keyField, prompt: Text("Paste your key from the Gumroad receipt"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .autocorrectionDisabled()
                    .onSubmit { submitLicenseKey() }
            }

            HStack {
                Button {
                    submitLicenseKey()
                } label: {
                    if license.isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(license.isVerifying || keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Buy a License…") {
                    NSWorkspace.shared.open(LicenseManager.purchaseURL)
                }
            }
            Text("$15 once, for the Macs you own. Stays valid offline for 14 days between checks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let licenseMessage {
                Label(licenseMessage, systemImage: messageIcon)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var licenseMessageForLastResult: String {
        switch license.lastVerificationResult {
        case .revoked:
            // Gumroad answers the same way for a mistyped key and a refunded
            // or disabled one, so the copy blames neither.
            return LicenseCopy.keyNotAccepted
        case .invalidKey:
            return "That key does not look like a Gumroad license key. Check it and try again."
        case .unreachable:
            return "Gumroad could not be reached. Connect to the internet and try again."
        case .valid, .none:
            return "The license could not be verified."
        }
    }

    private func submitLicenseKey() {
        guard !license.isVerifying,
              !keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submittedKey = keyField
        Task {
            // Two Return events may enqueue before the first task starts.
            guard !license.isVerifying else { return }
            let entitled = await license.verify(key: submittedKey)
            licenseMessage = entitled
                ? "License verified. Ping Protection is available."
                : licenseMessageForLastResult
            if entitled, keyField == submittedKey { keyField = "" }
        }
    }

    private var messageIcon: String {
        if case .valid = license.lastVerificationResult { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var messageIsError: Bool {
        if case .valid = license.lastVerificationResult { return false }
        return true
    }
}

// MARK: - Automation Settings Content

struct AutomationSettingsContent: View {
    @State private var gameModeAutoDetect = PingWardenPreferences.shared.gameModeAutoDetect
    @State private var controlCenterEnabled = PingWardenPreferences.shared.controlCenterWidgetEnabled
    @State private var controlCenterAvailability = ControlCenterSupport.availabilityForCurrentApp()
    @State private var screenRecordingPermissionGranted = GameModeDetector.hasScreenRecordingPermission()
    @State private var showingControlCenterConfirm = false
    @State private var showingScreenRecordingPermissionAlert = false

    var body: some View {
        Form {
            Section("Game Mode") {
                Toggle(isOn: $gameModeAutoDetect) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Game Mode Auto-Detect")
                            if gameModeAutoDetect && !screenRecordingPermissionGranted {
                                StatusBadge(text: "Fullscreen Detection Off", tint: .informational)
                            }
                        }
                        Text("Turn on protection and record a latency session while a game is running. Works from the frontmost app with no extra permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Game Mode Auto-Detect")
                .accessibilityHint("Recognizes a game from the frontmost app. Screen Recording permission adds fullscreen games behind other windows and never captures or saves screen contents")
                .onChangeCompat(of: gameModeAutoDetect) { newValue in
                    screenRecordingPermissionGranted = GameModeDetector.hasScreenRecordingPermission()
                    PingWardenPreferences.shared.gameModeAutoDetect = newValue
                }

                if gameModeAutoDetect && !screenRecordingPermissionGranted {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Screen Recording permission also catches a fullscreen game sitting behind other windows. Optional.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Enable Fullscreen Detection…") {
                            showingScreenRecordingPermissionAlert = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Toggle(isOn: $controlCenterEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Hide Menu Bar Icon")
                            if !controlCenterAvailability.isAvailable {
                                StatusBadge(text: controlCenterAvailability.statusText, tint: .unavailable)
                            }
                        }
                        Text(controlCenterAvailability.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Hide Menu Bar Icon")
                .accessibilityHint("Keeps Ping Warden in the Dock and uses the Control Center toggle instead of the menu bar icon")
                .disabled(!controlCenterAvailability.isAvailable)
                .onChangeCompat(of: controlCenterEnabled) { newValue in
                    if newValue {
                        showingControlCenterConfirm = true
                    } else {
                        PingWardenPreferences.shared.controlCenterWidgetEnabled = false
                    }
                }
            } header: {
                Text("Interface")
            } footer: {
                // Section footer carries the conditional help text. EmptyView()
                // collapses the footer when there's nothing relevant to say.
                if controlCenterAvailability.isAvailable && controlCenterEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controlCenterAvailability.footerText)
                        Text("Ping Warden stays in the Dock so settings remain available.")
                    }
                } else if !controlCenterAvailability.isAvailable {
                    Text(controlCenterAvailability.footerText)
                } else {
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeTreatment()
        .onAppear {
            refreshAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAvailability()
        }
        .alert("Enable Fullscreen Detection", isPresented: $showingScreenRecordingPermissionAlert) {
            Button("Open System Settings") {
                GameModeDetector.openScreenRecordingSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Game Mode auto-detect already recognizes a game when it is the frontmost app. Allowing Screen Recording lets it also notice a fullscreen game behind other windows. Ping Warden reads only window metadata and never captures or saves screen contents.")
        }
        .confirmationDialog(
            "Hide Menu Bar Icon?",
            isPresented: $showingControlCenterConfirm,
            titleVisibility: .visible
        ) {
            Button("Hide Menu Bar Icon") {
                PingWardenPreferences.shared.controlCenterWidgetEnabled = true
            }
            Button("Cancel", role: .cancel) {
                controlCenterEnabled = false
            }
        } message: {
            Text("The menu bar icon will be hidden, and Ping Warden will stay visible in the Dock. Add the Ping Protection control in System Settings if it is not already in Control Center.")
        }
    }

    private func refreshAvailability() {
        controlCenterAvailability = ControlCenterSupport.availabilityForCurrentApp()
        screenRecordingPermissionGranted = GameModeDetector.hasScreenRecordingPermission()
    }
}

// MARK: - Advanced Settings Content

struct AdvancedSettingsContent: View {
    private struct DiagnosticsSheetResult: Identifiable {
        let id = UUID()
        let export: DiagnosticsExporter.ExportResult
    }

    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared
    @State private var showingRepairConfirm = false
    @State private var showingRemovalConfirm = false
    /// Titled outcome of the helper test or Repair. Each case has its own
    /// title, so one alert serves both.
    @State private var resultAlert: HelperTestReport?
    @State private var diagnosticsResult: DiagnosticsSheetResult?
    @State private var isRunningHelperTest = false
    @State private var isExportingDiagnostics = false
    @State private var maintenanceErrorMessage: String?
    @State private var crashReportingRelaunchRequired = CrashReporter.relaunchRequired
    @State private var crashReportingEnabled = PingWardenPreferences.shared.isCrashReportingEnabled
    @State private var betaChannelEnabled = PingWardenPreferences.shared.betaChannelEnabled

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle(isOn: $crashReportingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Send Crash Reports")
                            if crashReportingRelaunchRequired {
                                StatusBadge(text: "Relaunch Required", tint: .unavailable)
                            }
                        }
                        Text("Sends anonymous crash reports without usage data or ping targets. Turning this off takes effect immediately. Turning it on takes effect after you relaunch Ping Warden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Send Crash Reports")
                .accessibilityHint(crashReportingRelaunchRequired
                    ? "Relaunch required to start sending anonymous crash reports. Sends no IP addresses, usage data, or ping targets."
                    : "Sends anonymous crash details without IP addresses, usage data, or ping targets")
                .onChangeCompat(of: crashReportingEnabled) { newValue in
                    PingWardenPreferences.shared.isCrashReportingEnabled = newValue
                    if !newValue { CrashReporter.stop() }
                    crashReportingRelaunchRequired = CrashReporter.relaunchRequired
                }
            }

            Section("Updates") {
                Toggle(isOn: $betaChannelEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receive Beta Updates")
                        Text("Opt in to pre-release builds. Betas may have bugs and are released ahead of the stable channel. Takes effect at the next update check.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Receive Beta Updates")
                .accessibilityHint("Switches future update checks between the stable and pre-release channels")
                .onChangeCompat(of: betaChannelEnabled) { newValue in
                    PingWardenPreferences.shared.betaChannelEnabled = newValue
                }
            }

            Section("Diagnostics") {
                LabeledContent {
                    Button {
                        runHelperTest()
                    } label: {
                        if isRunningHelperTest {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Run Test")
                        }
                    }
                        .buttonStyle(.bordered)
                        .disabled(isRunningHelperTest)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test Helper Connection")
                        Text("Check that the helper is set up and responding")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Button("Open Console") { openConsoleApp() }
                        .buttonStyle(.bordered)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View Logs")
                        Text("Open Console.app to view logs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Button {
                        exportDiagnostics()
                    } label: {
                        if isExportingDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Snapshot")
                        }
                    }
                        .buttonStyle(.bordered)
                        .disabled(isExportingDiagnostics)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics Snapshot")
                        Text("Create a private local text file for troubleshooting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Maintenance") {
                LabeledContent {
                    Button {
                        showingRepairConfirm = true
                    } label: {
                        if protectionExperience.isRepairingHelper {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Repair…")
                        }
                    }
                        .buttonStyle(.bordered)
                        .disabled(protectionExperience.isBusy || protectionExperience.isRepairingHelper)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repair Helper Connection")
                        Text(protectionExperience.isRepairingHelper
                            ? "Repairing the helper connection…"
                            : "Reconnect the approved helper without changing your protection preference")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Button("Prepare to Remove…") { showingRemovalConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove Ping Warden")
                        Text("Turn off protection, unregister the helper, clear local data, and quit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeTreatment()
        .confirmationDialog(
            "Repair Helper Connection?",
            isPresented: $showingRepairConfirm,
            titleVisibility: .visible
        ) {
            Button("Repair") {
                repairHelperConnection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ping Warden will check that the helper answers. If it does not, Ping Warden registers the helper again, which macOS may announce with a Background Items Added notification. Your protection preference, settings, and session history stay as they are.")
        }
        .confirmationDialog(
            "Prepare Ping Warden for Removal?",
            isPresented: $showingRemovalConfirm,
            titleVisibility: .visible
        ) {
            Button("Prepare to Remove", role: .destructive) {
                prepareForRemoval()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Matches clearLocalDataForRemoval: LicenseManager.resetForRemoval
            // deletes the saved key and the transition marker as well.
            Text("This turns off Ping Protection, unregisters the helper and Launch at Login, and deletes your settings, custom ping targets, latency session history, this Mac's saved license key, and its license transition status. Keep your Gumroad receipt to enter the key again. Ping Warden then shows the app in Finder and quits, so you can move it to the Trash.")
        }
        .alert(
            resultAlert?.title ?? "",
            isPresented: Binding(
                get: { resultAlert != nil },
                set: { if !$0 { resultAlert = nil } }
            )
        ) {
            Button("OK") { resultAlert = nil }
        } message: {
            Text(resultAlert?.message ?? "")
        }
        .sheet(item: $diagnosticsResult) { result in
            DiagnosticsResultView(result: result.export) {
                diagnosticsResult = nil
            }
        }
        .alert(
            "Maintenance Could Not Finish",
            isPresented: Binding(
                get: { maintenanceErrorMessage != nil },
                set: { if !$0 { maintenanceErrorMessage = nil } }
            )
        ) {
            Button("OK") { maintenanceErrorMessage = nil }
        } message: {
            Text(maintenanceErrorMessage ?? "Try again.")
        }
    }

    private func runHelperTest() {
        guard !isRunningHelperTest else { return }
        isRunningHelperTest = true
        DispatchQueue.global(qos: .userInitiated).async {
            let healthCheck = PingWardenMonitor.shared.performHealthCheck()
            let helperRegistered = PingWardenMonitor.shared.isHelperRegistered

            DispatchQueue.main.async {
                isRunningHelperTest = false
                resultAlert = HelperTestReport.make(
                    helperRegistered: helperRegistered,
                    isHealthy: healthCheck.isHealthy,
                    message: healthCheck.message
                )
            }
        }
    }

    private func openConsoleApp() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        isExportingDiagnostics = true
        DispatchQueue.global(qos: .utility).async {
            let result = DiagnosticsExporter.exportSnapshot()
            DispatchQueue.main.async {
                isExportingDiagnostics = false
                guard let result else {
                    maintenanceErrorMessage = "The diagnostics snapshot could not be created on the Desktop or in the temporary folder."
                    return
                }

                diagnosticsResult = DiagnosticsSheetResult(export: result)
            }
        }
    }

    private func repairHelperConnection() {
        let shouldRemainEnabled = PingWardenPreferences.shared.isMonitoringEnabled
        PingWardenMonitor.shared.repairHelperRegistration(presentsErrors: false) { repaired in
            Task { @MainActor in
                guard repaired else {
                    // A specific cause, such as a damaged app bundle, beats
                    // the general directions.
                    resultAlert = HelperTestReport(
                        title: RepairResultCopy.failureTitle,
                        message: PingWardenMonitor.shared.lastSetupFailureMessage
                            ?? RepairResultCopy.failureMessage
                    )
                    return
                }
                let restored = await protectionExperience.setPersistentProtection(shouldRemainEnabled)
                guard restored else {
                    maintenanceErrorMessage = "The helper is responding again, but Ping Warden could not restore your protection preference."
                    return
                }
                resultAlert = HelperTestReport(
                    title: RepairResultCopy.successTitle,
                    message: RepairResultCopy.successMessage(
                        protectionOn: PingWardenMonitor.shared.isMonitoringActive
                    )
                )
            }
        }
    }

    private func prepareForRemoval() {
        settingsLog.info("Preparing Ping Warden for removal")
        Task { @MainActor in
            let previousProtectionEnabled = PingWardenPreferences.shared.isMonitoringEnabled
            let launchAtLoginWasEnabled = SMAppService.mainApp.status == .enabled
            let helperService = SMAppService.daemon(
                plistName: "com.amesvt.pingwarden.helper.plist"
            )
            let helperWasEnabled = helperService.status == .enabled

            let stopped = await protectionExperience.setPersistentProtection(false)
            guard stopped else {
                maintenanceErrorMessage = "Ping Protection could not be turned off, so no settings were erased. Quit Ping Warden to restore wireless sharing, then try again."
                return
            }

            do {
                if SMAppService.mainApp.status == .enabled {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                settingsLog.error("Launch at Login unregister failed: \(error.localizedDescription)")
                let restored = await restoreRemovalState(
                    protectionEnabled: previousProtectionEnabled,
                    restoreLaunchAtLogin: false,
                    restoreHelper: false
                )
                maintenanceErrorMessage = removalFailureMessage(
                    "Launch at Login could not be unregistered. \(error.localizedDescription)",
                    restored: restored
                )
                return
            }

            do {
                if helperWasEnabled {
                    try await helperService.unregister()
                    settingsLog.info("Helper unregistered successfully")
                }
            } catch {
                settingsLog.error("Helper unregister failed: \(error.localizedDescription)")
                let restored = await restoreRemovalState(
                    protectionEnabled: previousProtectionEnabled,
                    restoreLaunchAtLogin: launchAtLoginWasEnabled,
                    restoreHelper: false
                )
                maintenanceErrorMessage = removalFailureMessage(
                    "The helper could not be unregistered. \(error.localizedDescription)",
                    restored: restored
                )
                return
            }

            do {
                try clearLocalDataForRemoval()
            } catch {
                settingsLog.error("Local data removal failed: \(error.localizedDescription)")
                let restored = await restoreRemovalState(
                    protectionEnabled: previousProtectionEnabled,
                    restoreLaunchAtLogin: launchAtLoginWasEnabled,
                    restoreHelper: helperWasEnabled
                )
                maintenanceErrorMessage = removalFailureMessage(
                    "Ping Warden could not clear its latency session history. \(error.localizedDescription)",
                    restored: restored
                )
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @MainActor
    private func restoreRemovalState(
        protectionEnabled: Bool,
        restoreLaunchAtLogin: Bool,
        restoreHelper: Bool
    ) async -> Bool {
        var restored = true

        if restoreLaunchAtLogin, SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                settingsLog.error("Launch at Login rollback failed: \(error.localizedDescription)")
                restored = false
            }
        }

        if restoreHelper {
            let helperService = SMAppService.daemon(
                plistName: "com.amesvt.pingwarden.helper.plist"
            )
            if helperService.status != .enabled {
                do {
                    try helperService.register()
                } catch {
                    settingsLog.error("Helper rollback failed: \(error.localizedDescription)")
                    restored = false
                }
            }

            if helperService.status == .enabled {
                let connected = await withCheckedContinuation { continuation in
                    PingWardenMonitor.shared.registerHelper { success in
                        continuation.resume(returning: success)
                    }
                }
                restored = connected && restored
            } else {
                restored = false
            }
        }

        let protectionRestored = await protectionExperience.setPersistentProtection(
            protectionEnabled
        )
        return protectionRestored && restored
    }

    private func removalFailureMessage(_ cause: String, restored: Bool) -> String {
        if restored {
            return "\(cause) Your previous Ping Warden settings were restored, and no local data was erased."
        }
        return "\(cause) Ping Warden could not fully restore the prior state. Open Settings → Advanced, click Repair, and review Launch at Login before retrying. No local data was erased."
    }

    private func clearLocalDataForRemoval() throws {
        // App Group preferences survive app deletion, so clear them only after
        // the helper has been turned off and unregistered successfully.
        try ProtectedSessionStore().removeAll()
        LicenseManager.shared.resetForRemoval()
        PingWardenPreferences.shared.isCrashReportingEnabled = false
        CrashReporter.stop()
        PingWardenPreferences.shared.resetForRemoval()
        GeForceNOWDiscovery.clearCache()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}

private struct DiagnosticsResultView: View {
    let result: DiagnosticsExporter.ExportResult
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnostics Snapshot Created")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(result.fileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ScrollView {
                Text(result.contents)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(copied ? "Copied" : "Copy Contents") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.contents, forType: .string)
                    copied = true
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 560)
    }
}

// MARK: - About View

struct AboutView: View {

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 64

    @ObservedObject private var license = LicenseManager.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 28)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: heroIconSize, height: heroIconSize)
                    .accessibilityHidden(true)

                Text("Ping Warden")
                    .font(.title)
                    .fontWeight(.semibold)
                    .padding(.top, 16)

                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Spacer(minLength: 28)

                Text("Keeps AWDL quiet to reduce Wi‑Fi lag while you cloud game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 28)

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        aboutLicenseLink
                        aboutWebsiteLink
                        aboutDocumentationLink
                        aboutIssueLink
                    }

                    VStack(spacing: 8) {
                        aboutLicenseLink
                        aboutWebsiteLink
                        aboutDocumentationLink
                        aboutIssueLink
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.top, 12)

                VStack(spacing: 12) {
                    Text("Credits")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        Link("jamestut/awdlkiller", destination: URL(string: "https://github.com/jamestut/awdlkiller") ?? URL(fileURLWithPath: "/"))
                            .font(.caption)

                        Text("AF_ROUTE monitoring concept")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Link("james-howard/AWDLControl", destination: URL(string: "https://github.com/james-howard/AWDLControl") ?? URL(fileURLWithPath: "/"))
                            .font(.caption)

                        Text("SMAppService + XPC architecture")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)

                Text("© 2025-2026 Oliver Ames")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 420, idealHeight: 480)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var aboutLicenseLink: some View {
        if license.hasValidPaidLicense {
            Text("Licensed")
                .foregroundStyle(.secondary)
        } else {
            Button("Buy a License") {
                NSWorkspace.shared.open(LicenseManager.purchaseURL)
            }
        }
    }

    private var aboutWebsiteLink: some View {
        Link("Website", destination: LicenseManager.websiteURL)
    }

    private var aboutDocumentationLink: some View {
        Link(
            "Documentation",
            destination: LicenseManager.documentationURL
        )
    }

    private var aboutIssueLink: some View {
        Link("Report an Issue", destination: Self.reportIssueURL)
    }

    /// Shared with the Help menu so both open the same issue chooser.
    static let reportIssueURL = URL(string: "https://github.com/oliverames/ping-warden/issues/new/choose")!
}

// MARK: - Game Mode Detector

/// Detects when a game is running so Ping Protection can engage on its own.
/// Two observation paths feed `GameModeActivationPolicy`: the frontmost app
/// (via `NSWorkspace` activation events, no permission needed) and a fullscreen
/// window owned by a game (via `CGWindowListCopyWindowInfo`, which needs Screen
/// Recording permission to expose window owners). Only apps that declare a game
/// category or LSSupportsGameMode in their Info.plist count, so a fullscreen
/// browser or productivity app never trips it. Engagement is skipped on a wired
/// path, because AWDL shares the Wi-Fi radio and cannot disturb Ethernet.
final class GameModeDetector: @unchecked Sendable {
    private let detectionQueue = DispatchQueue(
        label: "com.amesvt.pingwarden.game-mode-detection",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?
    /// Interval the current timer repeats at, so an idle tick replaces the
    /// timer only when the polling tier actually changes.
    private var timerInterval: TimeInterval?
    private var isRunning = false
    private var isGameModeActive = false
    private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "GameMode")
    /// Cache of pid → isGame to avoid re-reading Info.plist every 2 seconds.
    /// Entries are evicted via `appDidTerminateObserver` so the cache cannot
    /// outgrow the set of currently-running apps for the session.
    private var gameCheckCache: [pid_t: Bool] = [:]
    private var appDidTerminateObserver: NSObjectProtocol?
    private var appDidActivateObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var selfDidBecomeActiveObserver: NSObjectProtocol?
    /// Cached Screen Recording permission, read on `detectionQueue`.
    /// `CGPreflightScreenCaptureAccess` costs about 13 ms, too much for every
    /// tick, so it is read at start and again whenever Ping Warden becomes
    /// active, which is where someone lands after granting it in System
    /// Settings.
    private var screenRecordingGranted = false
    private var inactiveSamples = 0
    private var idleStreakTicks = 0
    /// PID of the frontmost app, captured on the main thread from activation
    /// events and read on `detectionQueue`, so no cross-queue sync is needed.
    private var frontmostPID: pid_t?
    private var pathMonitor: NWPathMonitor?
    private var pathInterface: GameModeActivationPolicy.PathInterface = .unknown
    /// NWPathMonitor delivers its first sample asynchronously, so the initial
    /// status check has to wait for it. Without this the check would run against
    /// the `.unknown` default, which fails toward protection, and a game already
    /// frontmost at start would briefly take AWDL down even on a wired path.
    private var hasPathSample = false

    private static let ignoredFullscreenOwners: Set<String> = [
        "Finder",
        "Dock",
        "Window Server",
        "SystemUIServer",
        "Control Center",
        "Notification Center"
    ]

    var onGameModeChange: ((Bool) -> Void)?

    deinit {
        timer?.cancel()
        if let observer = appDidTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = appDidActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = selfDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        // Ensure we're on the main thread for timer scheduling
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        // Screen Recording only gates the fullscreen path; the frontmost-app
        // path works without it, so this is a degraded mode rather than a failure.
        let screenRecordingGranted = Self.hasScreenRecordingPermission()
        if !screenRecordingGranted {
            log.warning("Screen Recording permission not granted - fullscreen game detection unavailable, frontmost-app detection still active")
        }

        let initialFrontmost = NSWorkspace.shared.frontmostApplication
        let initialFrontmostPID = GameModeActivationPolicy.shouldTrackActivation(bundleIdentifier: initialFrontmost?.bundleIdentifier)
            ? initialFrontmost?.processIdentifier : nil
        detectionQueue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            self.screenRecordingGranted = screenRecordingGranted
            self.frontmostPID = initialFrontmostPID
            self.startPathMonitor()
            // The first status check is driven by the path monitor's first
            // sample. The safety timer remains the backstop if none arrives,
            // where an unknown path correctly fails toward protection.
            self.scheduleSafetyTimer()
        }

        // Evict cache entries when their PID terminates so the cache cannot
        // grow unbounded over a long-running session. macOS reuses PIDs, so
        // keeping stale entries would also poison the cache after rollover.
        if appDidTerminateObserver == nil {
            appDidTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else {
                    return
                }
                self?.detectionQueue.async { [weak self] in
                    self?.gameCheckCache.removeValue(forKey: pid)
                }
            }
        }

        if appDidActivateObserver == nil {
            appDidActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // A permission prompt or password sheet over a game activates
                // briefly without the user leaving the game. Keep the game as
                // the tracked frontmost app so protection does not drop and
                // flap back when the dialog closes.
                guard GameModeActivationPolicy.shouldTrackActivation(bundleIdentifier: app?.bundleIdentifier) else {
                    return
                }
                let pid = app?.processIdentifier
                self?.detectionQueue.async { [weak self] in
                    self?.frontmostPID = pid
                }
                self?.scheduleGameModeStatusCheck()
            }
        }

        if screenParametersObserver == nil {
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleGameModeStatusCheck()
            }
        }

        if selfDidBecomeActiveObserver == nil {
            selfDidBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                let granted = Self.hasScreenRecordingPermission()
                self?.detectionQueue.async { [weak self] in
                    self?.screenRecordingGranted = granted
                }
            }
        }
    }

    func stop() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in self?.stop() }
            return
        }

        if let observer = appDidTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appDidTerminateObserver = nil
        }

        if let observer = appDidActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appDidActivateObserver = nil
        }

        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParametersObserver = nil
        }

        if let observer = selfDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            selfDidBecomeActiveObserver = nil
        }

        detectionQueue.sync {
            isRunning = false
            timer?.cancel()
            timer = nil
            timerInterval = nil
            pathMonitor?.cancel()
            pathMonitor = nil
            pathInterface = .unknown
            hasPathSample = false
            frontmostPID = nil
            gameCheckCache.removeAll()
            inactiveSamples = 0
            idleStreakTicks = 0

            if isGameModeActive {
                isGameModeActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onGameModeChange?(false)
                }
            }
        }
    }

    /// Check if Screen Recording permission is granted
    /// CGWindowListCopyWindowInfo requires this permission on macOS 10.15+ to get window names
    static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func scheduleGameModeStatusCheck() {
        detectionQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            // An activation or display change means the user just did
            // something; drop back to the responsive polling tier.
            self.idleStreakTicks = 0
            self.checkGameModeStatus()
        }
    }

    private func scheduleSafetyTimer() {
        dispatchPrecondition(condition: .onQueue(detectionQueue))
        timer?.cancel()

        let interval = GameModePollingPolicy.interval(
            isActive: isGameModeActive,
            idleStreakTicks: idleStreakTicks
        )
        timerInterval = interval
        let newTimer = DispatchSource.makeTimerSource(queue: detectionQueue)
        newTimer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 100))
        )
        newTimer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            self.checkGameModeStatus()
        }
        timer = newTimer
        newTimer.resume()
    }

    private func startPathMonitor() {
        dispatchPrecondition(condition: .onQueue(detectionQueue))
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.isRunning else { return }
            let interface = Self.pathInterface(for: path)
            let isFirstSample = !self.hasPathSample
            guard isFirstSample || interface != self.pathInterface else { return }
            self.hasPathSample = true
            self.pathInterface = interface
            self.log.info("Network path is now \(String(describing: interface), privacy: .public)")
            self.checkGameModeStatus()
        }
        monitor.start(queue: detectionQueue)
        pathMonitor = monitor
    }

    private static func pathInterface(for path: NWPath) -> GameModeActivationPolicy.PathInterface {
        guard path.status == .satisfied else { return .unknown }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .other
    }

    private func checkGameModeStatus() {
        dispatchPrecondition(condition: .onQueue(detectionQueue))
        let frontmostIsGame = frontmostPID.map { isAppAGame(pid: $0) } ?? false
        // The fullscreen scan is pointless without Screen Recording, since the
        // window list then carries no owner info; skip the walk in that case.
        let fullscreenGame = frontmostIsGame ? false
            : (screenRecordingGranted && isAnyAppFullscreen())
        let engage = GameModeActivationPolicy.shouldEngage(
            frontmostIsGame: frontmostIsGame,
            fullscreenGamePresent: fullscreenGame,
            pathInterface: pathInterface
        )

        if engage {
            inactiveSamples = 0
            idleStreakTicks = 0
            if !isGameModeActive {
                isGameModeActive = true
                log.info("Game Mode detected: true")
                scheduleSafetyTimer()
                DispatchQueue.main.async { [weak self] in
                    self?.onGameModeChange?(true)
                }
            }
            return
        }

        guard isGameModeActive else {
            inactiveSamples = 0
            idleStreakTicks += 1
            // Replace the repeating timer only when the streak crosses into
            // another tier, so that tier takes effect on the very next tick.
            // An event-driven check resets the streak and drops back here.
            let tierInterval = GameModePollingPolicy.interval(
                isActive: false,
                idleStreakTicks: idleStreakTicks
            )
            if tierInterval != timerInterval {
                scheduleSafetyTimer()
            }
            return
        }

        inactiveSamples += 1
        idleStreakTicks += 1
        guard inactiveSamples >= 2 else {
            return
        }

        inactiveSamples = 0
        isGameModeActive = false
        log.info("Game Mode detected: false")
        scheduleSafetyTimer()
        DispatchQueue.main.async { [weak self] in
            self?.onGameModeChange?(false)
        }
    }

    private func isAnyAppFullscreen() -> Bool {
        let displayBounds = Self.activeDisplayBounds()
        guard !displayBounds.isEmpty else { return false }

        // Get list of windows on screen
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            // Fullscreen app content should be a normal app window. Higher
            // layers are menu extras, overlays, panels, or system UI.
            guard let layer = window[kCGWindowLayer as String] as? Int32,
                  layer == 0 else {
                continue
            }

            // Get window bounds
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)

            // Check if window covers an active display.
            if Self.windowFrameCoversAnyDisplay(windowFrame, displayBounds: displayBounds) {
                // Get owner name and PID
                guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                      let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t else {
                    continue
                }

                guard ownerPID != ProcessInfo.processInfo.processIdentifier else {
                    continue
                }

                // Skip system apps that commonly go fullscreen
                if Self.ignoredFullscreenOwners.contains(ownerName) {
                    continue
                }

                // Check if this app is marked as a game
                if isAppAGame(pid: ownerPID) {
                    log.debug("Fullscreen game detected: \(ownerName)")
                    return true
                } else {
                    log.debug("Fullscreen app '\(ownerName)' is not a game, ignoring")
                }
            }
        }

        return false
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else { return [] }

        return displays.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
    }

    private static func windowFrameCoversAnyDisplay(_ windowFrame: CGRect, displayBounds: [CGRect]) -> Bool {
        displayBounds.contains { displayFrame in
            let intersection = windowFrame.intersection(displayFrame)
            guard !intersection.isNull, !intersection.isEmpty else {
                return false
            }
            return intersection.width >= displayFrame.width * 0.95 &&
                   intersection.height >= displayFrame.height * 0.95
        }
    }

    /// Checks if an app is categorized as a game by examining its Info.plist.
    /// Results are cached per-PID to avoid repeated disk I/O on the 2-second timer.
    private func isAppAGame(pid: pid_t) -> Bool {
        if let cached = gameCheckCache[pid] {
            return cached
        }
        let result = isAppAGameUncached(pid: pid)
        gameCheckCache[pid] = result
        return result
    }

    private func isAppAGameUncached(pid: pid_t) -> Bool {
        // Get the running application from PID
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleURL = app.bundleURL else {
            log.debug("Could not get bundle for PID \(pid)")
            return false
        }

        // Load the bundle to access Info.plist
        guard let bundle = Bundle(url: bundleURL),
              let infoPlist = bundle.infoDictionary else {
            log.debug("Could not load Info.plist for bundle: \(bundleURL.lastPathComponent)")
            return false
        }

        // Check LSApplicationCategoryType for game category. The generic
        // category is "public.app-category.games", but most titles declare a
        // subcategory like "public.app-category.action-games" or
        // "public.app-category.role-playing-games" — those end in "-games"
        // and do NOT share the generic prefix, so match both shapes.
        if let categoryType = infoPlist["LSApplicationCategoryType"] as? String {
            let isGameCategory = categoryType == "public.app-category.games" ||
                (categoryType.hasPrefix("public.app-category.") && categoryType.hasSuffix("-games"))
            if isGameCategory {
                log.debug("App \(bundleURL.lastPathComponent) has game category (\(categoryType))")
                return true
            }
        }

        // Check LSSupportsGameMode flag
        if let supportsGameMode = infoPlist["LSSupportsGameMode"] as? Bool, supportsGameMode {
            log.debug("App \(bundleURL.lastPathComponent) supports Game Mode")
            return true
        }

        return false
    }
}
// MARK: - Previews

#Preview("General Settings") {
    GeneralSettingsContent()
        .frame(width: 450, height: 400)
        .background(.regularMaterial)
}

#Preview("Automation Settings") {
    AutomationSettingsContent()
        .frame(width: 450, height: 300)
        .background(.regularMaterial)
}

#Preview("License Settings") {
    LicenseSettingsContent()
        .frame(width: 450, height: 350)
        .background(.regularMaterial)
}

#Preview("Advanced Settings") {
    AdvancedSettingsContent()
        .frame(width: 450, height: 350)
        .background(.regularMaterial)
}

#Preview("About View") {
    AboutView()
}

#Preview("Welcome View") {
    WelcomeView(
        onSetup: { completion in completion(true) },
        onOpenDashboard: {},
        onDismiss: {}
    )
}
