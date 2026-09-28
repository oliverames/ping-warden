// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import SwiftUI
import ServiceManagement

// MARK: - Welcome View

struct WelcomeView: View {
    static let defaultSize = NSSize(width: 540, height: 680)

    private enum SetupState: String, Equatable {
        case idle
        /// Repair is confirming or rebuilding an already approved helper.
        case checking
        case waiting
        case complete
        case failed
    }

    let onSetup: (@escaping @MainActor @Sendable (Bool) -> Void) -> Void
    let onOpenDashboard: () -> Void
    let onDismiss: () -> Void

    var onOpenLicenseSettings: () -> Void = {}
    @ObservedObject private var license = LicenseManager.shared
    @ObservedObject private var protectionExperience = ProtectionExperienceCoordinator.shared

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var setupState: SetupState = {
#if DEBUG
        let prefix = "--welcome-state="
        let value = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
        return value.flatMap { SetupState(rawValue: String($0)) } ?? .idle
#else
        return .idle
#endif
    }()

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            welcomeContent
                            Spacer(minLength: 0)
                            setupFooter
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        welcomeContent
                    }

                    setupFooter
                }
            }
        }
        .frame(minWidth: 480, idealWidth: Self.defaultSize.width,
               minHeight: 560, idealHeight: Self.defaultSize.height)
        .background(.background)
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)

                Text("Welcome to Ping Warden")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Keep your Wi\u{2011}Fi steady while you cloud game on a Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                WelcomeBenefitRow(
                    icon: "shield.lefthalf.filled",
                    title: "Reduce AWDL-related Wi‑Fi stutter",
                    description: "Ping Protection pauses the wireless sharing interface used by AirDrop while you play. Other sources of lag can still affect your connection."
                )
                WelcomeBenefitRow(
                    icon: "waveform.path.ecg",
                    title: "Watch latency live",
                    description: "See your ping, jitter, and probe failures in the free dashboard."
                )
                WelcomeBenefitRow(
                    icon: "airplayaudio",
                    title: "Share when you need to",
                    description: "Pause protection to use AirDrop, AirPlay, and Handoff."
                )
            }
            .frame(maxWidth: 400)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // The footer sits outside the scroll view, so the license line stays
    // visible whichever setup state grows the callout above the buttons.
    private var setupFooter: some View {
        VStack(spacing: 14) {
            setupCallout
                .frame(maxWidth: 400)
            setupButtons
            if !license.canEnableProtection {
                licenseLine
            }
            Text("Ping Warden sends anonymous crash reports. You can turn this off in Settings → Advanced.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
        }
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var licenseLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                licenseLineText
                licenseLineButton
            }
            VStack(spacing: 4) {
                licenseLineText
                licenseLineButton
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
    }

    private var licenseLineText: some View {
        Text("Ping Protection is a one-time $15 purchase.")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var licenseLineButton: some View {
        Button("Enter or Buy a License…", action: onOpenLicenseSettings)
            .buttonStyle(.link)
    }

    @ViewBuilder
    private var setupCallout: some View {
        switch setupState {
        case .idle:
            Text("Setup asks for one approval in \(SystemSettingsCopy.loginItemsPaneName).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .checking:
            progressCallout(
                title: "Checking the helper…",
                detail: "Ping Warden is confirming that its helper responds."
            )
        case .waiting:
            progressCallout(
                title: "Waiting for approval",
                detail: "In System Settings, allow Ping Warden under \(SystemSettingsCopy.loginItemsPaneName), then return here."
            )
        case .complete:
            Label(PingWardenMonitor.shared.isMonitoringActive
                ? "Setup complete. Ping Protection is on."
                : "Helper ready. Ping Protection is off.", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            VStack(spacing: 4) {
                Label("Setup did not finish", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Allow Ping Warden in \(SystemSettingsCopy.loginItemsPath), then click Try Again. If it is already allowed, restart your Mac and click Try Again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    private func progressCallout(title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var primaryAction: WelcomeSetupPolicy.PrimaryAction {
        WelcomeSetupPolicy.primaryAction(canEnableProtection: license.canEnableProtection)
    }

    private var setupButtons: some View {
        VStack(spacing: 12) {
            switch setupState {
            case .complete:
                openDashboardButton(prominent: true)
            case .waiting:
                openLoginItemsButton
                laterButton
            case .idle, .checking, .failed:
                switch primaryAction {
                case .setUpProtection:
                    setupButton(prominent: true)
                case .openDashboard:
                    openDashboardButton(prominent: true)
                    setupButton(prominent: false)
                }
                laterButton
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 240)
    }

    private var laterButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Not Now")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.link)
        .font(.callout)
        .accessibilityIdentifier("welcome.later")
    }

    private var openLoginItemsButton: some View {
        Button {
            SMAppService.openSystemSettingsLoginItems()
        } label: {
            Text("Open \(SystemSettingsCopy.loginItemsPaneName)")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("welcome.openLoginItems")
    }

    private var setupButtonTitle: String {
        if setupState == .failed { return "Try Again" }
        return license.canEnableProtection ? "Turn On Ping Protection" : "Set Up Ping Protection"
    }

    /// A repair started here or from Settings must not start twice: a
    /// second one would unregister the helper the first just rebuilt.
    private var setupInProgress: Bool {
        setupState == .checking || protectionExperience.isRepairingHelper
    }

    private func startSetup() {
        guard !setupInProgress else { return }
        switch WelcomeSetupPolicy.progress(helperRegistered: PingWardenMonitor.shared.isHelperRegistered) {
        case .checkingHelper:
            setupState = .checking
        case .waitingForApproval:
            setupState = .waiting
        }
        onSetup { success in
            DispatchQueue.main.async {
                setupState = success ? .complete : .failed
            }
        }
    }

    @ViewBuilder
    private func setupButton(prominent: Bool) -> some View {
        let button = Button(action: startSetup) {
            ZStack {
                Text(setupButtonTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(setupInProgress ? 0 : 1)
                if setupInProgress {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(setupInProgress)
        .controlSize(.large)
        .accessibilityLabel(setupButtonTitle)
        .accessibilityIdentifier("welcome.setup")

        if prominent {
            button
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func openDashboardButton(prominent: Bool) -> some View {
        let button = Button {
            onOpenDashboard()
        } label: {
            Text("Open Dashboard")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityIdentifier("welcome.openDashboard")

        if prominent {
            button
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }
}

private struct WelcomeBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
