import SwiftUI
import ServiceManagement
import os.log

private let log = Logger(subsystem: "com.awdlcontrol.app", category: "App")

@main
struct AWDLControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitoringObserver: NSObjectProtocol?
    private var controlCenterObserver: NSObjectProtocol?
    private var dockIconObserver: NSObjectProtocol?
    private var gameModeObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var gameModeDetector: GameModeDetector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("AWDLControl launching...")

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

        // Check if this is first launch (daemon not installed)
        if !monitor.isDaemonInstalled() {
            log.info("First launch detected - daemon not installed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showWelcomeWindow()
            }
        } else {
            log.info("Daemon already installed")
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
        if AWDLPreferences.shared.showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
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
            AWDLMonitor.shared.installAndStartMonitoring()
        } onDismiss: {
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
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

        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        log.debug("Setting up menu bar")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
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
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 650, height: 500))
        window.center()
        window.isReleasedWhenClosed = false

        // Add an empty toolbar to enable the unified toolbar style
        // This is what allows the sidebar to extend under the titlebar
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        settingsWindow = window
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
        window.title = "About AWDLControl"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false

        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isMonitoring = AWDLMonitor.shared.isMonitoringActive
        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AWDL Control")
        image?.isTemplate = true

        button.image = image
        button.toolTip = isMonitoring ? "AWDL Blocking: Active" : "AWDL Blocking: Inactive"
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
        let installed = AWDLMonitor.shared.isDaemonInstalled()

        if !installed {
            statusItem.title = "Status: Not Installed"
        } else if isMonitoring {
            statusItem.title = "Status: Blocking AWDL"
        } else {
            statusItem.title = "Status: AWDL Allowed"
        }
    }

    @objc private func toggleMonitoring() {
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
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)

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

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case automation = "Automation"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .automation: return "sparkles"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - AppKit Split View Controller for Finder-style Sidebar

class SettingsSplitViewController: NSSplitViewController {
    private var sidebarVC: NSViewController!
    private var detailVC: NSViewController!
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
        sidebarVC = NSHostingController(rootView: sidebarView)

        // Create detail view
        let detailView = SettingsDetailView(section: selectedSection)
        detailVC = NSHostingController(rootView: detailView)

        // Create split view items
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 220
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        splitView.dividerStyle = .thin
    }

    private func updateDetailView() {
        let newDetailView = SettingsDetailView(section: selectedSection)
        detailVC = NSHostingController(rootView: newDetailView)

        // Replace the detail split view item
        if splitViewItems.count > 1 {
            removeSplitViewItem(splitViewItems[1])
        }

        let detailItem = NSSplitViewItem(viewController: detailVC)
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

// Legacy SettingsView kept for reference but not used
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            SettingsContentView(section: selectedSection)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 650, height: 500)
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

private let settingsLog = Logger(subsystem: "com.awdlcontrol.app", category: "Settings")

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
    @State private var isDaemonInstalled = AWDLMonitor.shared.isDaemonInstalled()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDockIcon = AWDLPreferences.shared.showDockIcon
    @State private var timer: Timer?

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
                    .disabled(!isDaemonInstalled)
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
                        .onChange(of: showDockIcon) { _, newValue in
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

                    Text("Ping Warden uses a modern system daemon that requires only a one-time approval in System Settings. The daemon runs while the app is open and automatically restores AWDL when you quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                isMonitoring = AWDLMonitor.shared.isMonitoringActive
                isDaemonInstalled = AWDLMonitor.shared.isDaemonInstalled()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var statusColor: Color {
        if !isDaemonInstalled { return .gray }
        return isMonitoring ? .green : .orange
    }

    private var statusText: String {
        if !isDaemonInstalled { return "Not Installed" }
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
                            .onChange(of: gameModeAutoDetect) { _, newValue in
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
                            .onChange(of: controlCenterEnabled) { _, newValue in
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
                SettingsRow("Test Helper Response", description: "Verify the helper is responding quickly") {
                    Button("Run Test") {
                        runDaemonTest()
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

    private func runDaemonTest() {
        let healthCheck = AWDLMonitor.shared.performHealthCheck()

        if !healthCheck.isHealthy {
            testResults = "Health Check Failed:\n\(healthCheck.message)"
            showingTestResults = true
            return
        }

        let testScript = """
        echo "Testing AWDL daemon response time..."
        for i in 1 2 3 4 5; do
            ifconfig awdl0 up 2>/dev/null
            sleep 0.001
            if ifconfig awdl0 2>/dev/null | grep -q "UP"; then
                echo "Test $i: FAILED - AWDL still UP after 1ms"
            else
                echo "Test $i: PASSED - AWDL brought down in <1ms"
            fi
        done
        echo ""
        echo "Final AWDL status:"
        ifconfig awdl0 2>/dev/null | head -1
        """

        let appleScript = """
        do shell script "\(testScript.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
        """

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
            testResults = String(data: data, encoding: .utf8) ?? "No output"
            showingTestResults = true
        } catch {
            testResults = "Test error: \(error.localizedDescription)"
            showingTestResults = true
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
            let helperService = SMAppService.daemon(plistName: "com.awdlcontrol.helper.plist")
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

            VStack(spacing: 8) {
                Text("Based on awdlkiller by jamestut")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("View on GitHub") {
                    openURL(URL(string: "https://github.com/jamestut/awdlkiller")!)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.vertical, 16)

            Text("© 2025 Oliver Ames")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 16)
        }
        .frame(width: 280, height: 340)
        .background(.regularMaterial)
    }
}

// MARK: - Game Mode Detector

/// Detects when macOS Game Mode is active by monitoring for fullscreen apps
class GameModeDetector {
    private var timer: Timer?
    private var isGameModeActive = false
    private let log = Logger(subsystem: "com.awdlcontrol.app", category: "GameMode")

    var onGameModeChange: ((Bool) -> Void)?

    deinit {
        timer?.invalidate()
    }

    func start() {
        // Check immediately
        checkGameModeStatus()

        // Then check periodically (every 2 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkGameModeStatus()
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
                // Get owner name to filter out system apps
                if let ownerName = window[kCGWindowOwnerName as String] as? String {
                    // Skip system apps that commonly go fullscreen
                    let systemApps = ["Finder", "Dock", "Window Server", "SystemUIServer", "Control Center", "Notification Center"]
                    if systemApps.contains(ownerName) {
                        continue
                    }

                    log.debug("Fullscreen app detected: \(ownerName)")
                    return true
                }
            }
        }

        return false
    }
}
