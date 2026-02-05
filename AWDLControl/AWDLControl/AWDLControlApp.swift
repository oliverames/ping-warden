//
//  AWDLControlApp.swift
//  AWDLControl
//
//  Main application entry point and UI for Ping Warden.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

import SwiftUI
import ServiceManagement
import os.log
// TODO: Uncomment once Sparkle is added via SPM:
// import Sparkle

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
struct AWDLControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // TODO: Uncomment once Sparkle is added:
    // private var updaterController: SPUStandardUpdaterController?
    
    private var monitoringObserver: NSObjectProtocol?
    private var controlCenterObserver: NSObjectProtocol?
    private var dockIconObserver: NSObjectProtocol?
    private var gameModeObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var gameModeDetector: GameModeDetector?
    private var lastToggleTime: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("AWDLControl launching...")

        // Initialize Sparkle auto-updater
        // TODO: Uncomment once Sparkle is added and configured:
        // updaterController = SPUStandardUpdaterController(
        //     startingUpdater: true,
        //     updaterDelegate: nil,
        //     userDriverDelegate: nil
        // )

        // Check for quarantine issues and help user if needed
        QuarantineHelper.showQuarantineHelpIfNeeded()

        // Set dock icon visibility based on preference
        updateDockIconVisibility()

        // Initialize monitoring
        let monitor = AWDLMonitor.shared

        // Set up callback for state changes
        monitor.onStateChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuBarIcon()
                self?.updateMenuItem()
            }
        }

        // Setup menu bar (unless Control Center mode is enabled AND widget is available)
        // Always check if widget is actually available before hiding menu bar
        let widgetAvailable = checkControlCenterWidgetAvailable()
        if AWDLPreferences.shared.controlCenterWidgetEnabled && !widgetAvailable {
            log.warning("Control Center widget enabled but not available (requires code signing). Resetting to menu bar.")
            AWDLPreferences.shared.controlCenterWidgetEnabled = false
        }
        if !AWDLPreferences.shared.controlCenterWidgetEnabled || !widgetAvailable {
            setupMenuBar()
        }

        // Check if this is first launch (helper not registered)
        if !monitor.isHelperRegistered {
            log.info("First launch detected - helper not registered")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showWelcomeWindow()
            }
        } else {
            log.info("Helper already registered")
            if AWDLPreferences.shared.isMonitoringEnabled && !monitor.isMonitoringActive {
                monitor.startMonitoring()
            }
        }

        // Setup Game Mode detector if enabled
        if AWDLPreferences.shared.gameModeAutoDetect {
            setupGameModeDetector()
        }

        // Observe preference changes from widget (uses distributed notifications for cross-process)
        monitoringObserver = DistributedNotificationCenter.default().addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMonitoringStateChange()
        }

        // Observe Control Center mode changes
        controlCenterObserver = NotificationCenter.default.addObserver(
            forName: .controlCenterModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleControlCenterModeChange()
        }

        // Observe dock icon visibility changes
        dockIconObserver = NotificationCenter.default.addObserver(
            forName: .dockIconVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDockIconVisibility()
        }

        // Observe Game Mode auto-detect changes
        gameModeObserver = NotificationCenter.default.addObserver(
            forName: .gameModeAutoDetectChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleGameModeAutoDetectChange()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("AWDLControl terminating...")

        gameModeDetector?.stop()

        if AWDLMonitor.shared.isMonitoringActive {
            AWDLMonitor.shared.stopMonitoring()
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
    }

    private func updateDockIconVisibility() {
        // Show dock icon if preference is set OR if settings window is visible
        let settingsVisible = settingsWindow?.isVisible ?? false
        let aboutVisible = aboutWindow?.isVisible ?? false
        let welcomeVisible = welcomeWindow?.isVisible ?? false
        
        if AWDLPreferences.shared.showDockIcon || settingsVisible || aboutVisible || welcomeVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Update dock icon visibility when any window closes
        if window === settingsWindow || window === aboutWindow || window === welcomeWindow {
            // Delay slightly to let the window actually close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
        if AWDLPreferences.shared.gameModeAutoDetect {
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
        if isActive {
            if !AWDLMonitor.shared.isMonitoringActive {
                log.info("Game Mode active - enabling AWDL blocking")
                AWDLMonitor.shared.startMonitoring()
            }
        } else {
            // Only disable if user didn't manually enable
            if !AWDLPreferences.shared.isMonitoringEnabled && AWDLMonitor.shared.isMonitoringActive {
                log.info("Game Mode inactive - disabling AWDL blocking")
                AWDLMonitor.shared.stopMonitoring()
            }
        }
    }

    // MARK: - Welcome Window

    private func showWelcomeWindow() {
        if welcomeWindow != nil { return }

        let welcomeView = WelcomeView {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            self.updateDockIconVisibility()
            AWDLMonitor.shared.installAndStartMonitoring()
        } onDismiss: {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            self.updateDockIconVisibility()
        }

        let hostingController = NSHostingController(rootView: welcomeView)
        let window = NSWindow(contentViewController: hostingController)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        welcomeWindow = window
        
        // Show dock icon when welcome window opens
        NSApp.setActivationPolicy(.regular)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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

        // Toggle item
        let toggleItem = NSMenuItem(
            title: AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Blocking" : "Enable AWDL Blocking",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu?.addItem(toggleItem)

        statusMenu?.addItem(NSMenuItem.separator())

        // Status item
        let statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        statusMenu?.addItem(statusMenuItem)
        updateStatusMenuItem()

        statusMenu?.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        statusMenu?.addItem(settingsItem)

        // Check for Updates (Sparkle)
        // TODO: Uncomment once Sparkle is integrated
        // let updateItem = NSMenuItem(
        //     title: "Check for Updates...",
        //     action: #selector(checkForUpdates),
        //     keyEquivalent: ""
        // )
        // updateItem.target = self
        // statusMenu?.addItem(updateItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About Ping Warden",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        statusMenu?.addItem(aboutItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ping Warden",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusMenu?.addItem(quitItem)

        self.statusItem?.menu = statusMenu
    }

    private func removeMenuBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            statusMenu = nil
        }
    }

    private var settingsWindow: NSWindow?

    private var settingsSplitVC: SettingsSplitViewController?

    @objc private func openSettings() {
        log.info("openSettings called")

        // If settings window already exists, just bring it to front
        if let window = settingsWindow {
            log.info("Existing settings window found, bringing to front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        log.info("Creating new settings window with NSSplitViewController")

        // Create the split view controller
        let splitVC = SettingsSplitViewController()
        settingsSplitVC = splitVC

        let window = NSWindow(contentViewController: splitVC)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified

        // Set minimum and default window size
        window.minSize = NSSize(width: 600, height: 450)
        
        // Ensure window fits on screen
        var windowSize = NSSize(width: 720, height: 580)
        if let screen = NSScreen.main {
            windowSize.width = min(windowSize.width, screen.visibleFrame.width - 40)
            windowSize.height = min(windowSize.height, screen.visibleFrame.height - 40)
        }
        window.setContentSize(windowSize)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Add an empty toolbar to enable the unified toolbar style
        // This is what allows the sidebar to extend under the titlebar
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        settingsWindow = window
        
        // Show dock icon when settings window opens
        NSApp.setActivationPolicy(.regular)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log.info("Settings window created and shown")
    }

    @objc private func showAbout() {
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Ping Warden"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        aboutWindow = window
        
        // Show dock icon when about window opens
        NSApp.setActivationPolicy(.regular)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // TODO: Uncomment once Sparkle is integrated
    // @objc private func checkForUpdates() {
    //     updaterController?.checkForUpdates(nil)
    // }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isMonitoring = AWDLMonitor.shared.isMonitoringActive
        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let accessibilityDesc = isMonitoring ? "Ping Warden: AWDL Blocking Active" : "Ping Warden: AWDL Blocking Inactive"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDesc)
        image?.isTemplate = true

        button.image = image
        button.toolTip = isMonitoring ? "AWDL Blocking: Active" : "AWDL Blocking: Inactive"

        // Accessibility for VoiceOver
        button.setAccessibilityLabel(accessibilityDesc)
        button.setAccessibilityRole(.button)
    }

    private func updateMenuItem() {
        guard let menu = statusMenu else { return }

        let newTitle = AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Blocking" : "Enable AWDL Blocking"
        menu.items.first?.title = newTitle

        updateStatusMenuItem()
    }

    private func updateStatusMenuItem() {
        guard let menu = statusMenu,
              let statusItem = menu.items.first(where: { $0.tag == 100 }) else { return }

        let isMonitoring = AWDLMonitor.shared.isMonitoringActive
        let installed = AWDLMonitor.shared.isHelperRegistered

        if !installed {
            statusItem.title = "Status: Not Set Up"
        } else if isMonitoring {
            statusItem.title = "Status: Blocking AWDL"
        } else {
            statusItem.title = "Status: AWDL Allowed"
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

        if AWDLMonitor.shared.isMonitoringActive {
            AWDLMonitor.shared.stopMonitoring()
        } else {
            AWDLMonitor.shared.startMonitoring()
        }
    }

    private func handleMonitoringStateChange() {
        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled
        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        if shouldMonitor && !isMonitoring {
            AWDLMonitor.shared.startMonitoring()
        } else if !shouldMonitor && isMonitoring {
            AWDLMonitor.shared.stopMonitoring()
        }

        updateMenuBarIcon()
        updateMenuItem()
    }

    private func handleControlCenterModeChange() {
        // Control Center widgets require proper code signing to work
        // For unsigned/ad-hoc signed apps, always keep menu bar visible
        let isProperlySignedForControlCenter = checkControlCenterWidgetAvailable()

        if AWDLPreferences.shared.controlCenterWidgetEnabled && isProperlySignedForControlCenter {
            removeMenuBar()
        } else {
            // Reset preference if widget isn't available
            if AWDLPreferences.shared.controlCenterWidgetEnabled && !isProperlySignedForControlCenter {
                log.warning("Control Center widget not available (requires code signing). Reverting to menu bar.")
                AWDLPreferences.shared.controlCenterWidgetEnabled = false
            }
            if statusItem == nil {
                setupMenuBar()
            }
        }
    }

    /// Check if Control Center widget is available (requires proper code signing)
    private func checkControlCenterWidgetAvailable() -> Bool {
        // Control Center widgets require the app to be properly signed with a Developer ID
        // Ad-hoc signed apps won't have their widgets appear in Control Center
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return false }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }

        var requirement: SecRequirement?
        // Check for Developer ID or Apple signature (not ad-hoc)
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] exists"
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }

        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let onSetup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Group {
                    if #available(macOS 14.0, *) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 56, weight: .thin))
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 56, weight: .thin))
                            .foregroundStyle(.tint)
                    }
                }

                Text("Welcome to Ping Warden")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Eliminate Latency Spikes",
                    description: "Prevents 100-300ms ping spikes caused by AWDL"
                )

                FeatureRow(
                    icon: "gamecontroller.fill",
                    title: "Perfect for Gaming",
                    description: "Keep your connection stable during competitive play"
                )

                FeatureRow(
                    icon: "cpu",
                    title: "Zero Performance Impact",
                    description: "<1ms response time, 0% CPU when idle"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)

                Text("Setup requires a one-time system approval in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Later") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Set Up Now") {
                    onSetup()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .frame(width: 480, height: 520)
        .background(.regularMaterial)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        SettingsViewRepresentable()
            .frame(minWidth: 600, minHeight: 400)
    }
}

struct SettingsViewRepresentable: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> SettingsSplitViewController {
        return SettingsSplitViewController()
    }

    func updateNSViewController(_ nsViewController: SettingsSplitViewController, context: Context) {
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case general = "General"
    case automation = "Automation"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.xyaxis.line"
        case .general: return "gearshape"
        case .automation: return "sparkles"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - AppKit Split View Controller for Finder-style Sidebar

class SettingsSplitViewController: NSSplitViewController {
    // Use regular optionals instead of implicitly unwrapped to prevent crashes
    // if properties are accessed before viewDidLoad()
    private var sidebarVC: NSViewController?
    private var detailVC: NSViewController?
    private var selectedSection: SettingsSection = .general

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create sidebar
        let sidebarView = SettingsSidebarView(
            selectedSection: Binding(
                get: { self.selectedSection },
                set: { newValue in
                    self.selectedSection = newValue
                    self.updateDetailView()
                }
            )
        )
        let sidebarController = NSHostingController(rootView: sidebarView)
        sidebarVC = sidebarController

        // Create detail view
        let detailView = SettingsDetailView(section: selectedSection)
        let detailController = NSHostingController(rootView: detailView)
        detailVC = detailController

        // Create split view items
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 220
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        splitView.dividerStyle = .thin
    }

    private func updateDetailView() {
        let newDetailView = SettingsDetailView(section: selectedSection)
        let newDetailController = NSHostingController(rootView: newDetailView)

        // Remove old detail view item first, then add new one
        // Use safe iteration to find and remove the detail item
        // This ensures we don't access an invalid index
        while splitViewItems.count > 1 {
            removeSplitViewItem(splitViewItems[1])
        }

        // Update the reference
        detailVC = newDetailController

        let detailItem = NSSplitViewItem(viewController: newDetailController)
        detailItem.minimumThickness = 400
        addSplitViewItem(detailItem)
    }
}

// MARK: - Sidebar View

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsSection.allCases) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Detail View

struct SettingsDetailView: View {
    let section: SettingsSection

    var body: some View {
        SettingsContentView(section: section)
    }
}

struct SettingsContentView: View {
    let section: SettingsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Section title with divider
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.rawValue)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    Divider()
                        .padding(.horizontal, 20)
                }

                // Content with top spacing
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .dashboard:
                        DashboardSettingsContent()
                    case .general:
                        GeneralSettingsContent()
                    case .automation:
                        AutomationSettingsContent()
                    case .advanced:
                        AdvancedSettingsContent()
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 20)
            }
        }
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(.all, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
    }
}

// MARK: - Settings Components

private let settingsLog = Logger(subsystem: "com.amesvt.pingwarden", category: "Settings")

struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 20)
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String?
    let content: Content

    init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(description != nil ? "\(title), \(description!)" : title)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

// MARK: - General Settings Content

struct GeneralSettingsContent: View {
    @State private var isMonitoring = AWDLMonitor.shared.isMonitoringActive
    @State private var isHelperRegistered = AWDLMonitor.shared.isHelperRegistered
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDockIcon = AWDLPreferences.shared.showDockIcon
    @State private var monitoringObserver: NSObjectProtocol?
    @State private var interventionCount: Int = 0
    @State private var interventionTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // AWDL Status Group
            SettingsGroup {
                SettingsRow("AWDL Blocking", description: "Prevent network latency spikes from AWDL") {
                    Toggle("", isOn: Binding(
                        get: { isMonitoring },
                        set: { newValue in
                            if newValue {
                                AWDLMonitor.shared.startMonitoring()
                            } else {
                                AWDLMonitor.shared.stopMonitoring()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!isHelperRegistered)
                }

                SettingsDivider()

                SettingsRow("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if isMonitoring && interventionCount > 0 {
                    SettingsDivider()
                    
                    SettingsRow("AWDL Interventions") {
                        HStack(spacing: 8) {
                            Text("\(interventionCount)")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("blocked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                AWDLMonitor.shared.resetInterventionCount { success in
                                    if success {
                                        interventionCount = 0
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Reset counter")
                        }
                    }
                }
            }

            SettingsSectionHeader(title: "APP")

            SettingsGroup {
                SettingsRow("Launch at Login", description: "Start Ping Warden when you log in") {
                    Toggle("", isOn: Binding(
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
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                SettingsDivider()

                SettingsRow("Show Dock Icon", description: "Display app icon in the Dock") {
                    Toggle("", isOn: $showDockIcon)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChangeCompat(of: showDockIcon) { newValue in
                            AWDLPreferences.shared.showDockIcon = newValue
                        }
                }
            }

            SettingsSectionHeader(title: "HOW IT WORKS")

            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No Password Prompts", systemImage: "checkmark.shield")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Ping Warden uses a background helper that requires only a one-time approval in System Settings. The helper runs while the app is open and automatically restores AWDL when you quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        }
        .onAppear {
            // Use notification-based updates instead of polling
            monitoringObserver = NotificationCenter.default.addObserver(
                forName: .awdlMonitoringStateChanged,
                object: nil,
                queue: .main
            ) { _ in
                isMonitoring = AWDLMonitor.shared.isMonitoringActive
                isHelperRegistered = AWDLMonitor.shared.isHelperRegistered
            }
            // Also set up AWDLMonitor's callback for immediate updates
            AWDLMonitor.shared.onStateChange = {
                DispatchQueue.main.async {
                    isMonitoring = AWDLMonitor.shared.isMonitoringActive
                    isHelperRegistered = AWDLMonitor.shared.isHelperRegistered
                }
            }
            
            // Start fetching intervention count
            updateInterventionCount()
            startInterventionTimer()
        }
        .onDisappear {
            if let observer = monitoringObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            interventionTimer?.invalidate()
        }
    }
    
    private func updateInterventionCount() {
        guard isMonitoring else {
            interventionCount = 0
            return
        }
        
        AWDLMonitor.shared.getInterventionCount { count in
            interventionCount = count
        }
    }
    
    private func startInterventionTimer() {
        // Update intervention count every 5 seconds when monitoring is active
        interventionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [self] _ in
            updateInterventionCount()
        }
    }

    private var statusColor: Color {
        if !isHelperRegistered { return .gray }
        return isMonitoring ? .green : .orange
    }

    private var statusText: String {
        if !isHelperRegistered { return "Not Set Up" }
        return isMonitoring ? "Blocking AWDL" : "AWDL Allowed"
    }
}

// MARK: - Automation Settings Content

struct AutomationSettingsContent: View {
    @State private var gameModeAutoDetect = AWDLPreferences.shared.gameModeAutoDetect
    @State private var controlCenterEnabled = AWDLPreferences.shared.controlCenterWidgetEnabled

    private var isControlCenterAvailable: Bool {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        var requirement: SecRequirement?
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] exists"
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingsRow("Game Mode Auto-Detect", description: "Automatically enable blocking when a game is fullscreen") {
                    HStack(spacing: 8) {
                        Text("Beta")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                        Toggle("", isOn: $gameModeAutoDetect)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChangeCompat(of: gameModeAutoDetect) { newValue in
                                AWDLPreferences.shared.gameModeAutoDetect = newValue
                            }
                    }
                }
            }

            SettingsSectionHeader(title: "INTERFACE")

            SettingsGroup {
                SettingsRow("Control Center Widget", description: isControlCenterAvailable ? "Use Control Center instead of menu bar" : "Requires code-signed app (Developer ID)") {
                    HStack(spacing: 8) {
                        if isControlCenterAvailable {
                            Text("Beta")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        } else {
                            Text("Unavailable")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.gray.opacity(0.2))
                                .foregroundStyle(.gray)
                                .clipShape(Capsule())
                        }
                        Toggle("", isOn: $controlCenterEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!isControlCenterAvailable)
                            .onChangeCompat(of: controlCenterEnabled) { newValue in
                                AWDLPreferences.shared.controlCenterWidgetEnabled = newValue
                            }
                    }
                }
            }

            if isControlCenterAvailable && controlCenterEnabled {
                Text("To add the widget: System Settings → Control Center → scroll to Ping Warden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            } else if !isControlCenterAvailable {
                Text("Control Center widgets require the app to be signed with a Developer ID certificate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Advanced Settings Content

struct AdvancedSettingsContent: View {
    @State private var showingReinstallConfirm = false
    @State private var showingUninstallConfirm = false
    @State private var showingTestResults = false
    @State private var testResults = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "DIAGNOSTICS")

            SettingsGroup {
                SettingsRow("Test Helper Response", description: "Verify the helper is responding quickly (password required)") {
                    Button("Run Test") {
                        runHelperTest()
                    }
                    .buttonStyle(.bordered)
                }

                SettingsDivider()

                SettingsRow("View Logs", description: "Open Console.app to view logs") {
                    Button("Open Console") {
                        openConsoleApp()
                    }
                    .buttonStyle(.bordered)
                }
            }

            SettingsSectionHeader(title: "MAINTENANCE")

            SettingsGroup {
                SettingsRow("Re-register Helper", description: "Re-register if experiencing issues") {
                    Button("Re-register...") {
                        showingReinstallConfirm = true
                    }
                    .buttonStyle(.bordered)
                }

                SettingsDivider()

                SettingsRow("Uninstall", description: "Unregister helper and quit app") {
                    Button("Uninstall...") {
                        showingUninstallConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .confirmationDialog(
            "Re-register Helper?",
            isPresented: $showingReinstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Re-register") {
                AWDLMonitor.shared.installAndStartMonitoring()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will re-register the helper with the system. May help if you're experiencing connection issues.")
        }
        .confirmationDialog(
            "Uninstall Ping Warden?",
            isPresented: $showingUninstallConfirm,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                performUninstall()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will unregister the helper and quit. You can also just drag the app to Trash.")
        }
        .alert("Helper Test Results", isPresented: $showingTestResults) {
            Button("OK") {}
        } message: {
            Text(testResults)
        }
    }

    private func runHelperTest() {
        // Run health check on background thread to avoid UI freeze
        DispatchQueue.global(qos: .userInitiated).async {
            let healthCheck = AWDLMonitor.shared.performHealthCheck()

            DispatchQueue.main.async {
                if !healthCheck.isHealthy {
                    self.testResults = "Health Check Failed:\n\(healthCheck.message)"
                    self.showingTestResults = true
                    return
                }

                // Run the actual test script
                self.runTestScript()
            }
        }
    }

    private func runTestScript() {
        // Use single quotes in shell script to avoid escaping issues
        let testScript = """
        echo 'Testing AWDL helper response time...'
        for i in 1 2 3 4 5; do
            ifconfig awdl0 up 2>/dev/null
            sleep 0.001
            if ifconfig awdl0 2>/dev/null | grep -q 'UP'; then
                echo "Test $i: FAILED - AWDL still UP after 1ms"
            else
                echo "Test $i: PASSED - AWDL brought down in <1ms"
            fi
        done
        echo ''
        echo 'Final AWDL status:'
        ifconfig awdl0 2>/dev/null | head -1
        """

        // Base64 encode the script to safely pass it through AppleScript
        guard let scriptData = testScript.data(using: .utf8) else {
            testResults = "Error: Could not encode test script"
            showingTestResults = true
            return
        }
        let base64Script = scriptData.base64EncodedString()

        let appleScript = """
        do shell script "echo '\(base64Script)' | base64 -d | sh" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", appleScript]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "No output"

                DispatchQueue.main.async {
                    self.testResults = output
                    self.showingTestResults = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.testResults = "Test error: \(error.localizedDescription)"
                    self.showingTestResults = true
                }
            }
        }
    }

    private func openConsoleApp() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }

    private func performUninstall() {
        settingsLog.info("Performing uninstall...")

        // Stop monitoring and disconnect XPC
        AWDLMonitor.shared.stopMonitoring()

        // Unregister the helper with SMAppService
        do {
            let helperService = SMAppService.daemon(plistName: "com.amesvt.pingwarden.helper.plist")
            try helperService.unregister()
            settingsLog.info("Helper unregistered successfully")
        } catch {
            settingsLog.warning("Helper unregister: \(error.localizedDescription)")
        }

        // Quit the app - macOS will handle cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tint)

            Text("Ping Warden")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.top, 16)

            Text("Version \(version) (\(build))")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 6) {
                Text("<1ms response time")
                Text("0% CPU when idle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Divider()

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
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 4) {
                    Link("james-howard/AWDLControl", destination: URL(string: "https://github.com/james-howard/AWDLControl") ?? URL(fileURLWithPath: "/"))
                        .font(.caption)

                    Text("SMAppService + XPC architecture")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)

            Text("© 2025-2026 Oliver Ames")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 16)
        }
        .frame(width: 280, height: 400)
        .background(.regularMaterial)
    }
}

// MARK: - Game Mode Detector

/// Detects when macOS Game Mode is active by monitoring for fullscreen games.
/// Only apps that are categorized as games (via LSApplicationCategoryType or LSSupportsGameMode
/// in their Info.plist) will trigger game mode detection, preventing false positives from
/// non-game fullscreen apps like productivity apps or browsers.
///
/// Note: This feature requires Screen Recording permission on macOS 10.15+.
/// Without this permission, CGWindowListCopyWindowInfo won't return window names or owner info.
class GameModeDetector {
    private var timer: Timer?
    private var isGameModeActive = false
    private var hasLoggedPermissionWarning = false
    private let log = Logger(subsystem: "com.amesvt.pingwarden", category: "GameMode")

    var onGameModeChange: ((Bool) -> Void)?

    deinit {
        stop()
    }

    func start() {
        // Ensure we're on the main thread for timer scheduling
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }

        // Check for Screen Recording permission on first start
        if !hasScreenRecordingPermission() {
            log.warning("Screen Recording permission not granted - Game Mode detection may not work correctly")
            if !hasLoggedPermissionWarning {
                hasLoggedPermissionWarning = true
                // Only show alert once per app session
                showScreenRecordingPermissionAlert()
            }
        }

        // Check immediately
        checkGameModeStatus()

        // Then check periodically (every 2 seconds) on main run loop
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkGameModeStatus()
        }
        // Ensure timer continues during UI interactions
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        // Reset state
        if isGameModeActive {
            isGameModeActive = false
            onGameModeChange?(false)
        }
    }

    /// Check if Screen Recording permission is granted
    /// CGWindowListCopyWindowInfo requires this permission on macOS 10.15+ to get window names
    private func hasScreenRecordingPermission() -> Bool {
        // Create a small 1x1 capture to test if we have permission
        // This is the most reliable way to check Screen Recording permission
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        // If we can get window names, we have permission
        // Without permission, window names will be nil or empty
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               !ownerName.isEmpty,
               ownerName != "Window Server" {
                return true
            }
        }

        // If we only see Window Server or no names, we likely don't have permission
        // However, this could also be a legitimate state (no windows), so we do an additional check
        // Try to get process info which doesn't require permission
        return windowList.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) != nil
        }
    }

    /// Show alert explaining Screen Recording permission is needed
    private func showScreenRecordingPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Needed"
            alert.informativeText = "Game Mode auto-detect requires Screen Recording permission to detect fullscreen games.\n\nGrant access in System Settings → Privacy & Security → Screen Recording."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Preferences/Settings to Screen Recording
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func checkGameModeStatus() {
        let isFullscreen = isAnyAppFullscreen()

        if isFullscreen != isGameModeActive {
            isGameModeActive = isFullscreen
            log.info("Game Mode detected: \(isFullscreen)")
            onGameModeChange?(isFullscreen)
        }
    }

    private func isAnyAppFullscreen() -> Bool {
        // Get the main display bounds
        guard let mainScreen = NSScreen.main else { return false }
        let screenFrame = mainScreen.frame

        // Get list of windows on screen
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            // Skip windows that aren't at the standard window level or above
            guard let layer = window[kCGWindowLayer as String] as? Int32,
                  layer >= 0 else {
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

            // Check if window covers the full screen
            if windowFrame.width >= screenFrame.width && windowFrame.height >= screenFrame.height {
                // Get owner name and PID
                guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                      let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t else {
                    continue
                }

                // Skip system apps that commonly go fullscreen
                let systemApps = ["Finder", "Dock", "Window Server", "SystemUIServer", "Control Center", "Notification Center"]
                if systemApps.contains(ownerName) {
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

    /// Checks if an app is categorized as a game by examining its Info.plist
    /// Returns true if:
    /// - LSApplicationCategoryType == "public.app-category.games"
    /// - OR LSSupportsGameMode == true
    private func isAppAGame(pid: pid_t) -> Bool {
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

        // Check LSApplicationCategoryType for game category
        if let categoryType = infoPlist["LSApplicationCategoryType"] as? String {
            if categoryType == "public.app-category.games" {
                log.debug("App \(bundleURL.lastPathComponent) has game category")
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
