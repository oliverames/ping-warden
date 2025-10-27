import SwiftUI

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
    private var observer: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var isSyncing = false  // Prevent duplicate syncs

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize monitoring
        _ = AWDLMonitor.shared

        print("AWDLControl: App launched, monitoring state: \(AWDLMonitor.shared.isMonitoringActive)")

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
        print("AWDLControl: App terminating, stopping daemon...")

        if AWDLMonitor.shared.isMonitoringActive {
            AWDLMonitor.shared.stopMonitoring()
            AWDLPreferences.shared.isMonitoringEnabled = false  // Save disabled state

            // Verify daemon actually stopped
            sleep(1)  // Give launchctl time to unload
            let stillRunning = AWDLMonitor.shared.isMonitoringActive
            if stillRunning {
                print("AWDLControl: ⚠️ WARNING: Daemon still running after unload!")
            } else {
                print("AWDLControl: ✅ Verified daemon stopped, AWDL will be available for AirDrop/Handoff")
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

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusMenu?.addItem(quitItem)

        statusItem?.menu = statusMenu
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
        NSLog("AWDLControlApp: ========== toggleMonitoring() CALLED ==========")

        // Use AWDLMonitor which actually controls the daemon
        if AWDLMonitor.shared.isMonitoringActive {
            NSLog("AWDLControlApp: Stopping monitoring")
            AWDLMonitor.shared.stopMonitoring()
        } else {
            NSLog("AWDLControlApp: Starting monitoring")
            AWDLMonitor.shared.startMonitoring()
        }

        NSLog("AWDLControlApp: Updating UI")
        // Give the daemon a moment to start/stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.updateMenuBarIcon()
            self.updateMenuItem()
        }
        NSLog("AWDLControlApp: ========== toggleMonitoring() COMPLETE ==========")
    }

    private func syncMonitoringState() {
        // Prevent duplicate syncs (e.g., multiple notification events)
        guard !isSyncing else {
            print("AWDLControl: Sync already in progress, skipping")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled
        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

        print("AWDLControl: Syncing state - Preference: \(shouldMonitor), Daemon: \(isMonitoring)")

        if shouldMonitor && !isMonitoring {
            print("AWDLControl: Starting monitoring (triggered by preference change)")
            AWDLMonitor.shared.startMonitoring()
            updateMenuBarIcon()
            updateMenuItem()
        } else if !shouldMonitor && isMonitoring {
            print("AWDLControl: Stopping monitoring (triggered by preference change)")
            AWDLMonitor.shared.stopMonitoring()
            updateMenuBarIcon()
            updateMenuItem()
        } else {
            print("AWDLControl: States already in sync, no action needed")
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
