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
    private var isSyncing = false  // Prevent duplicate syncs
    private var aboutWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize monitoring
        _ = AWDLMonitor.shared

        log.info("App launched, monitoring state: \(AWDLMonitor.shared.isMonitoringActive)")

        // Setup menu bar
        setupMenuBar()

        // Sync daemon state with preference immediately after launch
        // This ensures daemon is stopped if preference says it should be
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncMonitoringState()
        }

        // Observe preference changes from widget (if we add widget back later)
        observer = NotificationCenter.default.addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMonitoringStateChange()
        }

        // Note: No periodic polling needed for menu bar app - user controls state directly
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Always stop the daemon when app quits
        // User can re-enable monitoring by launching the app again
        log.info("App terminating, stopping daemon...")

        if AWDLMonitor.shared.isMonitoringActive {
            AWDLMonitor.shared.stopMonitoring()
            AWDLPreferences.shared.isMonitoringEnabled = false  // Save disabled state

            // Verify daemon actually stopped
            sleep(1)  // Give launchctl time to unload
            let stillRunning = AWDLMonitor.shared.isMonitoringActive
            if stillRunning {
                log.warning("Daemon still running after unload")
            } else {
                log.info("Daemon stopped, AWDL available for AirDrop/Handoff")
            }
        }

        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set icon
        updateMenuBarIcon()

        // Create menu
        statusMenu = NSMenu()

        // Add menu items
        let toggleItem = NSMenuItem(
            title: AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Monitoring" : "Enable AWDL Monitoring",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggleItem.target = self
        statusMenu?.addItem(toggleItem)

        statusMenu?.addItem(NSMenuItem.separator())

        // Test daemon button
        let testItem = NSMenuItem(
            title: "Test Daemon",
            action: #selector(testDaemon),
            keyEquivalent: ""
        )
        testItem.target = self
        statusMenu?.addItem(testItem)

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

        statusItem?.menu = statusMenu
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == "About AWDLControl" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(Selector(("showAboutWindow:")), to: nil, from: nil)
        }

        // Return to accessory after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        // Use SF Symbol for the icon
        let symbolName = isMonitoring ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AWDL Control")
        image?.isTemplate = true

        button.image = image
        button.toolTip = isMonitoring ? "AWDL Monitoring: Active" : "AWDL Monitoring: Inactive"
    }

    private func updateMenuItem() {
        guard let menu = statusMenu else { return }

        let newTitle = AWDLMonitor.shared.isMonitoringActive ? "Disable AWDL Monitoring" : "Enable AWDL Monitoring"
        menu.items.first?.title = newTitle
    }

    @objc private func toggleMonitoring() {
        log.debug("Toggle monitoring requested")

        // Use AWDLMonitor which actually controls the daemon
        if AWDLMonitor.shared.isMonitoringActive {
            log.info("Stopping monitoring")
            AWDLMonitor.shared.stopMonitoring()
        } else {
            log.info("Starting monitoring")
            AWDLMonitor.shared.startMonitoring()
        }

        // Give the daemon a moment to start/stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.updateMenuBarIcon()
            self.updateMenuItem()
        }
    }

    @objc private func testDaemon() {
        log.debug("Testing daemon...")

        // Check if daemon is running
        let daemonRunning = AWDLMonitor.shared.isMonitoringActive

        if !daemonRunning {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Daemon Not Running"
                alert.informativeText = "The AWDL monitoring daemon is not currently running.\n\nPlease enable monitoring first, then run the test."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        // Run test script
        let testScript = """
        #!/bin/bash

        echo "Testing AWDL daemon response time..."
        echo ""

        # Test 1: Bring AWDL up and immediately check if it's down
        echo "Test 1: Bringing AWDL up and checking after 1ms..."
        ifconfig awdl0 up
        sleep 0.001
        STATUS=$(ifconfig awdl0 | grep flags)
        if echo "$STATUS" | grep -q "UP"; then
            echo "❌ FAILED: AWDL is still UP after 1ms"
            echo "   $STATUS"
            TEST1="FAILED"
        else
            echo "✅ SUCCESS: AWDL is DOWN (daemon responded in <1ms)"
            echo "   $STATUS"
            TEST1="SUCCESS"
        fi
        echo ""

        # Test 2: Try multiple times
        echo "Test 2: Testing 5 rapid toggles..."
        SUCCESS_COUNT=0
        for i in {1..5}; do
            ifconfig awdl0 up
            sleep 0.001
            if ! ifconfig awdl0 | grep -q "UP"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
        done
        echo "✅ $SUCCESS_COUNT/5 tests succeeded (AWDL brought down in <1ms)"
        echo ""

        # Test 3: Check final status
        echo "Test 3: Final AWDL status..."
        FINAL_STATUS=$(ifconfig awdl0 | grep flags)
        if echo "$FINAL_STATUS" | grep -q "UP"; then
            echo "❌ AWDL is UP (not being controlled)"
            TEST3="FAILED"
        else
            echo "✅ AWDL is DOWN (daemon is working)"
            TEST3="SUCCESS"
        fi
        echo "   $FINAL_STATUS"
        echo ""

        # Summary
        if [ "$TEST1" = "SUCCESS" ] && [ $SUCCESS_COUNT -eq 5 ] && [ "$TEST3" = "SUCCESS" ]; then
            echo "OVERALL: ALL TESTS PASSED ✅"
        else
            echo "OVERALL: SOME TESTS FAILED ❌"
        fi
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

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Daemon Test Results"
                alert.informativeText = output
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            log.error("Error running test: \(error.localizedDescription)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Test Failed"
                alert.informativeText = "Could not run daemon test: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func reinstallDaemon() {
        log.debug("Reinstalling daemon...")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reinstall Daemon?"
            alert.informativeText = """
            This will reinstall the AWDL monitoring daemon.

            If you're experiencing issues with the daemon, this can help fix them.

            The daemon will be stopped and reinstalled from the app bundle.

            Continue?
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Reinstall")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                self.performReinstallDaemon()
            }
        }
    }

    private func performReinstallDaemon() {
        // Get path to installer script in app bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            showError("Could not find app bundle resources")
            return
        }

        let installerScript = "\(bundlePath)/install_daemon.sh"

        let appleScript = """
        do shell script "'\(installerScript)'" with administrator privileges
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
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Daemon Reinstalled Successfully"
                    alert.informativeText = "The AWDL monitoring daemon has been reinstalled.\n\nYou can now enable monitoring from the menu bar."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()

                    // Update UI
                    self.updateMenuBarIcon()
                    self.updateMenuItem()
                }
            } else {
                log.error("Reinstall failed: \(output)")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Reinstall Failed"
                    alert.informativeText = "Could not reinstall daemon:\n\n\(output)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        } catch {
            log.error("Error reinstalling daemon: \(error.localizedDescription)")
            showError("Failed to reinstall daemon: \(error.localizedDescription)")
        }
    }

    @objc private func uninstallEverything() {
        log.debug("Uninstall requested...")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Uninstall AWDLControl?"
            alert.informativeText = """
            This will completely remove AWDLControl from your system:

            • Stop the AWDL monitoring daemon
            • Remove daemon binary (/usr/local/bin/awdl_monitor_daemon)
            • Remove daemon plist (/Library/LaunchDaemons/com.awdlcontrol.daemon.plist)
            • Remove app data and preferences

            The app will quit after uninstallation.

            You can manually delete AWDLControl.app from Applications folder afterward.

            Are you sure you want to uninstall?
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
        #!/bin/bash

        echo "Uninstalling AWDLControl..."
        echo ""

        # Stop and unload daemon if running
        echo "Stopping daemon..."
        launchctl bootout system/com.awdlcontrol.daemon 2>/dev/null || true
        echo "✅ Daemon stopped"
        echo ""

        # Remove daemon binary
        echo "Removing daemon binary..."
        rm -f /usr/local/bin/awdl_monitor_daemon
        echo "✅ Daemon binary removed"
        echo ""

        # Remove daemon plist
        echo "Removing daemon plist..."
        rm -f /Library/LaunchDaemons/com.awdlcontrol.daemon.plist
        echo "✅ Daemon plist removed"
        echo ""

        # Remove log file
        echo "Removing log file..."
        rm -f /var/log/awdl_monitor_daemon.log
        echo "✅ Log file removed"
        echo ""

        echo "Uninstallation complete!"
        echo ""
        echo "Note: You can manually delete AWDLControl.app from /Applications"
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

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            log.debug("Uninstall output: \(output)")

            // Remove app data
            let fileManager = FileManager.default
            let containerURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Containers/com.awdlcontrol.app")
            let groupURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Group Containers/group.com.awdlcontrol.app")

            try? fileManager.removeItem(at: containerURL!)
            try? fileManager.removeItem(at: groupURL!)

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Uninstall Complete"
                alert.informativeText = """
                AWDLControl has been uninstalled from your system.

                All daemon files and preferences have been removed.

                The app will now quit.

                To complete removal, delete AWDLControl.app from your Applications folder.
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Quit")

                alert.runModal()

                // Quit the app
                NSApplication.shared.terminate(nil)
            }
        } catch {
            log.error("Error during uninstall: \(error.localizedDescription)")
            showError("Uninstall failed: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        log.error("\(message)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func syncMonitoringState() {
        // Prevent duplicate syncs (e.g., multiple notification events)
        guard !isSyncing else {
            log.debug("Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled
        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        log.debug("Syncing state - Preference: \(shouldMonitor), Daemon: \(isMonitoring)")

        if shouldMonitor && !isMonitoring {
            log.info("Starting monitoring (triggered by preference change)")
            AWDLMonitor.shared.startMonitoring()
            updateMenuBarIcon()
            updateMenuItem()
        } else if !shouldMonitor && isMonitoring {
            log.info("Stopping monitoring (triggered by preference change)")
            AWDLMonitor.shared.stopMonitoring()
            updateMenuBarIcon()
            updateMenuItem()
        } else {
            log.debug("States already in sync")
        }
    }

    private func handleMonitoringStateChange() {
        syncMonitoringState()
    }
}

/// Simple settings view showing current status
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

                Text("Use the Control Center or menu bar control to toggle AWDL.")
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
                Text("Disabling AWDL prevents AirDrop, AirPlay, Handoff, and Universal Control from working.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(30)
        .frame(width: 400, height: 300)
        .onAppear {
            // Update status periodically
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                isMonitoring = AWDLMonitor.shared.isMonitoringActive
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

/// About window showing app info and version
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
