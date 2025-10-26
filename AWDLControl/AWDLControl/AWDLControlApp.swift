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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize monitoring (will restore previous state if enabled)
        _ = AWDLMonitor.shared

        print("AWDLControl: App launched, monitoring state: \(AWDLMonitor.shared.isMonitoringActive)")

        // Setup menu bar
        setupMenuBar()

        // Observe preference changes from widget
        observer = NotificationCenter.default.addObserver(
            forName: .awdlMonitoringStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMonitoringStateChange()
        }

        // Also poll for preference changes periodically
        setupPreferenceObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Keep monitoring enabled even when app quits
        // The monitoring state is persisted and will resume on next launch
        print("AWDLControl: App terminating, monitoring will resume on next launch")

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
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
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
        let isCurrentlyMonitoring = AWDLMonitor.shared.isMonitoringActive

        if isCurrentlyMonitoring {
            AWDLMonitor.shared.stopMonitoring()
            AWDLPreferences.shared.isMonitoringEnabled = false
        } else {
            AWDLMonitor.shared.startMonitoring()
            AWDLPreferences.shared.isMonitoringEnabled = true
        }

        updateMenuBarIcon()
        updateMenuItem()
    }

    private func setupPreferenceObserver() {
        // Poll for preference changes periodically
        // This ensures we catch changes made by the widget
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.syncMonitoringState()
        }
    }

    private func syncMonitoringState() {
        let shouldMonitor = AWDLPreferences.shared.isMonitoringEnabled
        let isMonitoring = AWDLMonitor.shared.isMonitoringActive

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
