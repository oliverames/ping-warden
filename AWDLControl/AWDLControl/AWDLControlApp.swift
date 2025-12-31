import SwiftUI
import os.log

private let log = Logger(subsystem: "com.awdlcontrol.app", category: "App")

@main
struct AWDLControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        Window("About AWDLControl", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var aboutWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("AWDLControl App launching...")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize monitoring
        let monitor = AWDLMonitor.shared

        // Set up callback for state changes
        monitor.onStateChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuBarIcon()
                self?.updateMenuItem()
            }
        }

        log.info("Initial monitoring state: \(monitor.isMonitoringActive)")

        // Setup menu bar
        setupMenuBar()

        // Check if this is first launch (daemon not installed)
        if !monitor.isDaemonInstalled() {
            log.info("First launch detected - daemon not installed")
            // Show welcome and trigger installation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showFirstLaunchWelcome()
            }
        } else {
            log.info("Daemon already installed")
            // If preference says enabled but daemon not running, start it
            if AWDLPreferences.shared.isMonitoringEnabled && !monitor.isMonitoringActive {
                log.info("Preference says enabled, starting daemon...")
                monitor.startMonitoring()
            }
        }

        // Observe preference changes from widget
        observer = NotificationCenter.default.addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            log.debug("Received monitoring state change notification")
            self?.handleMonitoringStateChange()
        }

        log.info("App launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("AWDLControl App terminating...")
        log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Stop daemon when app quits
        if AWDLMonitor.shared.isMonitoringActive {
            log.info("Stopping daemon before quit...")
            AWDLMonitor.shared.stopMonitoring()
        }

        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }

        log.info("App termination complete")
    }

    // MARK: - First Launch

    private func showFirstLaunchWelcome() {
        log.info("Showing first launch welcome")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Welcome to AWDLControl!"
            alert.informativeText = """
            AWDLControl keeps your network stable by disabling AWDL (Apple Wireless Direct Link), which can cause latency spikes during gaming or video calls.

            To get started, we need to install a small system daemon. This requires your admin password (one time only).

            Would you like to set up AWDLControl now?
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Set Up Now")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                log.info("User chose to set up now")
                AWDLMonitor.shared.installAndStartMonitoring()
            } else {
                log.info("User chose to set up later")
            }
        }
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
            title: AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Monitoring" : "Enable AWDL Monitoring",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu?.addItem(toggleItem)

        statusMenu?.addItem(NSMenuItem.separator())

        // Status item
        let statusItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusItem.tag = 100  // Tag for easy lookup
        statusMenu?.addItem(statusItem)
        updateStatusMenuItem()

        statusMenu?.addItem(NSMenuItem.separator())

        // Test daemon button
        let testItem = NSMenuItem(
            title: "Test Daemon",
            action: #selector(testDaemon),
            keyEquivalent: ""
        )
        testItem.target = self
        statusMenu?.addItem(testItem)

        // View Logs button
        let logsItem = NSMenuItem(
            title: "View Logs in Console",
            action: #selector(openConsoleApp),
            keyEquivalent: ""
        )
        logsItem.target = self
        statusMenu?.addItem(logsItem)

        statusMenu?.addItem(NSMenuItem.separator())

        // Reinstall daemon button
        let reinstallItem = NSMenuItem(
            title: "Reinstall Daemon",
            action: #selector(reinstallDaemon),
            keyEquivalent: ""
        )
        reinstallItem.target = self
        statusMenu?.addItem(reinstallItem)

        // Uninstall button
        let uninstallItem = NSMenuItem(
            title: "Uninstall Everything",
            action: #selector(uninstallEverything),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        statusMenu?.addItem(uninstallItem)

        statusMenu?.addItem(NSMenuItem.separator())

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

        log.debug("Menu bar setup complete")
    }

    @objc private func showAbout() {
        log.debug("Showing about window")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == "About AWDLControl" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(Selector(("showAboutWindow:")), to: nil, from: nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func openConsoleApp() {
        log.info("Opening Console app for log viewing")

        // Open Console app
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                          configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error {
                log.error("Failed to open Console: \(error.localizedDescription)")
            }
        }

        // Show instructions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert = NSAlert()
            alert.messageText = "Viewing AWDLControl Logs"
            alert.informativeText = """
            In Console.app:

            1. Click "Start Streaming" in the toolbar
            2. In the search field, enter:
               subsystem:com.awdlcontrol

            This will show all AWDLControl logs in realtime.

            Tip: You can also filter by category:
            • category:App - App lifecycle
            • category:Monitor - Daemon control
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AWDL Control")
        image?.isTemplate = true

        button.image = image
        button.toolTip = isMonitoring ? "AWDL Monitoring: Active (AWDL blocked)" : "AWDL Monitoring: Inactive (AWDL available)"

        log.debug("Menu bar icon updated: monitoring=\(isMonitoring)")
    }

    private func updateMenuItem() {
        guard let menu = statusMenu else { return }

        let newTitle = AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Monitoring" : "Enable AWDL Monitoring"
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
            statusItem.title = "Status: Active (AWDL blocked)"
        } else {
            statusItem.title = "Status: Inactive (AWDL available)"
        }
    }

    // MARK: - Actions

    @objc private func toggleMonitoring() {
        log.info("Toggle monitoring requested by user")

        if AWDLMonitor.shared.isMonitoringActive {
            log.info("Stopping monitoring...")
            AWDLMonitor.shared.stopMonitoring()
        } else {
            log.info("Starting monitoring...")
            AWDLMonitor.shared.startMonitoring()
        }

        // UI updates happen via onStateChange callback
    }

    @objc private func testDaemon() {
        log.info("Test daemon requested")

        let healthCheck = AWDLMonitor.shared.performHealthCheck()

        if !healthCheck.isHealthy {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Daemon Health Check"
                alert.informativeText = "Status: \(healthCheck.message)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        // Run response time test
        log.info("Running response time test...")

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
            let output = String(data: data, encoding: .utf8) ?? "No output"

            log.info("Test results:\n\(output)")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Daemon Test Results"
                alert.informativeText = output
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            log.error("Test error: \(error.localizedDescription)")
        }
    }

    @objc private func reinstallDaemon() {
        log.info("Reinstall daemon requested")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reinstall Daemon?"
            alert.informativeText = "This will reinstall the AWDL monitoring daemon.\n\nUseful if you're experiencing issues."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Reinstall")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                log.info("User confirmed reinstall")
                AWDLMonitor.shared.installAndStartMonitoring()
            }
        }
    }

    @objc private func uninstallEverything() {
        log.info("Uninstall requested")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Uninstall AWDLControl?"
            alert.informativeText = """
            This will completely remove AWDLControl:

            • Stop the AWDL monitoring daemon
            • Remove daemon binary and plist
            • Remove app data

            The app will quit after uninstallation.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Uninstall")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                self.performUninstall()
            }
        }
    }

    private func performUninstall() {
        log.info("Performing uninstall...")

        let uninstallScript = """
        # Stop daemon
        launchctl bootout system/com.awdlcontrol.daemon 2>/dev/null || true

        # Remove files
        rm -f /usr/local/bin/awdl_monitor_daemon
        rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
        rm -f /var/log/awdl_monitor_daemon.log

        echo "Uninstall complete"
        """

        let appleScript = """
        do shell script "\(uninstallScript.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
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

            log.info("Uninstall script completed with exit code: \(task.terminationStatus)")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Uninstall Complete"
                alert.informativeText = "AWDLControl has been uninstalled.\n\nThe app will now quit."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Quit")
                alert.runModal()

                NSApplication.shared.terminate(nil)
            }
        } catch {
            log.error("Uninstall error: \(error.localizedDescription)")
        }
    }

    private func handleMonitoringStateChange() {
        log.debug("Handling monitoring state change from widget/external")

        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled
        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        if shouldMonitor && !isMonitoring {
            log.info("Widget requested start - starting monitoring")
            AWDLMonitor.shared.startMonitoring()
        } else if !shouldMonitor && isMonitoring {
            log.info("Widget requested stop - stopping monitoring")
            AWDLMonitor.shared.stopMonitoring()
        }

        updateMenuBarIcon()
        updateMenuItem()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var isMonitoring = AWDLMonitor.shared.isMonitoringActive
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("AWDL Control")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .fontWeight(.semibold)
                    Text(isMonitoring ? "Monitoring Active" : "Inactive")
                        .foregroundColor(isMonitoring ? .green : .secondary)
                }

                Text("Use the menu bar to toggle AWDL monitoring.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.headline)
                Text("Keeps the AWDL interface down to prevent network ping spikes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Disabling AWDL prevents AirDrop, AirPlay, Handoff, and Universal Control.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(30)
        .frame(width: 400, height: 300)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                isMonitoring = AWDLMonitor.shared.isMonitoringActive
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - About View

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("AWDLControl")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Keeps AWDL disabled to eliminate network latency spikes.")
                    .font(.callout)
                    .multilineTextAlignment(.center)

                Text("<1ms response time • 0% CPU when idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 4) {
                Text("Based on [awdlkiller](https://github.com/jamestut/awdlkiller)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("© 2024 Oliver Ames")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(30)
        .frame(width: 320, height: 340)
    }
}
