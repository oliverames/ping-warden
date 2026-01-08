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

        // Setup menu bar (unless Control Center mode is enabled)
        if !AWDLPreferences.shared.controlCenterWidgetEnabled {
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
            title: "About AWDLControl",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        statusMenu?.addItem(aboutItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit AWDLControl",
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

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        if AWDLPreferences.shared.controlCenterWidgetEnabled {
            removeMenuBar()
        } else {
            if statusItem == nil {
                setupMenuBar()
            }
        }
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

                Text("Welcome to AWDLControl")
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

                Text("Setup requires your admin password once to install a system daemon.")
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
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettingsTab: View {
    @State private var isMonitoring = AWDLMonitor.shared.isMonitoringActive
    @State private var isDaemonInstalled = AWDLMonitor.shared.isDaemonInstalled()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var timer: Timer?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enable AWDL Blocking", isOn: Binding(
                    get: { isMonitoring },
                    set: { newValue in
                        if newValue {
                            AWDLMonitor.shared.startMonitoring()
                        } else {
                            AWDLMonitor.shared.stopMonitoring()
                        }
                    }
                ))
                .disabled(!isDaemonInstalled)
            } header: {
                Text("AWDL Control")
            } footer: {
                Text("When enabled, AWDL is kept disabled to prevent network latency spikes. AirDrop, AirPlay, and Handoff will not work while active.")
            }

            Section {
                Toggle("Launch at Login", isOn: Binding(
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
                            log.error("Failed to update login item: \(error.localizedDescription)")
                        }
                    }
                ))
            } header: {
                Text("Startup")
            } footer: {
                Text("Recommended: When enabled, the daemon starts at boot and the app launches at login. This reduces password prompts since the daemon is already running.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("About Password Prompts", systemImage: "lock.shield")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Your admin password is required to start or stop the system daemon that monitors AWDL. This is a macOS security requirement for system-level services.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("To minimize prompts: Enable \"Launch at Login\" above. The daemon will start automatically at boot, so toggling AWDL blocking won't require a password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
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

private let log = Logger(subsystem: "com.awdlcontrol.app", category: "Settings")

struct AdvancedSettingsTab: View {
    @State private var controlCenterEnabled = AWDLPreferences.shared.controlCenterWidgetEnabled
    @State private var gameModeAutoDetect = AWDLPreferences.shared.gameModeAutoDetect
    @State private var showDockIcon = AWDLPreferences.shared.showDockIcon
    @State private var showingReinstallConfirm = false
    @State private var showingUninstallConfirm = false
    @State private var showingTestResults = false
    @State private var testResults = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $controlCenterEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Control Center Widget")
                            Text("Beta")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Text("Use Control Center instead of menu bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: controlCenterEnabled) { _, newValue in
                    AWDLPreferences.shared.controlCenterWidgetEnabled = newValue
                }

                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        AWDLPreferences.shared.showDockIcon = newValue
                    }
            } header: {
                Text("Interface")
            } footer: {
                if controlCenterEnabled {
                    Text("To add the widget: System Settings → Control Center → scroll to AWDLControl. The menu bar icon will be hidden.")
                }
            }

            Section {
                Toggle(isOn: $gameModeAutoDetect) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Auto-Enable with Game Mode")
                            Text("Beta")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Text("Automatically enable when a game is fullscreen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: gameModeAutoDetect) { _, newValue in
                    AWDLPreferences.shared.gameModeAutoDetect = newValue
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("Detects when macOS Game Mode activates and automatically enables AWDL blocking.")
            }

            Section {
                Button("Test Daemon Response Time") {
                    runDaemonTest()
                }

                Button("View Logs in Console") {
                    openConsoleApp()
                }
            } header: {
                Text("Diagnostics")
            }

            Section {
                Button("Reinstall Daemon...") {
                    showingReinstallConfirm = true
                }
                .confirmationDialog(
                    "Reinstall Daemon?",
                    isPresented: $showingReinstallConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reinstall") {
                        AWDLMonitor.shared.installAndStartMonitoring()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will reinstall the AWDL monitoring daemon. Useful if you're experiencing issues.")
                }

                Button("Uninstall Everything...", role: .destructive) {
                    showingUninstallConfirm = true
                }
                .confirmationDialog(
                    "Uninstall AWDLControl?",
                    isPresented: $showingUninstallConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Uninstall", role: .destructive) {
                        performUninstall()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove the daemon and all app data. The app will quit after uninstallation.")
                }
            } header: {
                Text("Maintenance")
            }
        }
        .formStyle(.grouped)
        .alert("Daemon Test Results", isPresented: $showingTestResults) {
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
        let uninstallScript = """
        launchctl bootout system/com.awdlcontrol.daemon 2>/dev/null || true
        rm -f /usr/local/bin/awdl_monitor_daemon
        rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
        rm -f /var/log/awdl_monitor_daemon.log
        """

        let appleScript = """
        do shell script "\(uninstallScript.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]

        do {
            try task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            log.error("Uninstall error: \(error.localizedDescription)")
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

            Text("AWDLControl")
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
