// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import SwiftUI

// MARK: - Window content

/// The setup window: the first-run introduction, Finish Setup, and Repair's
/// approval step. One window, one primary button per screen.
struct OnboardingView: View {
    static let defaultSize = NSSize(width: 540, height: 600)
    static let minimumSize = NSSize(width: 480, height: 560)

    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    screen
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }
            }
            footer
        }
        .frame(minWidth: Self.minimumSize.width, idealWidth: Self.defaultSize.width,
               minHeight: Self.minimumSize.height, idealHeight: Self.defaultSize.height)
        .background(.background)
        .overlay(alignment: .topTrailing) {
            if model.mode == .repair {
                // Level with the window controls in the transparent title bar.
                RepairBadge()
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.step)
    }

    @ViewBuilder
    private var screen: some View {
        Group {
            switch model.step {
            case .welcome: WelcomeScreen()
            case .protection: ProtectionScreen(model: model)
            case .license: LicenseScreen(model: model)
            case .approve: ApproveScreen(model: model)
            case .done: DoneScreen(model: model)
            case .freeDashboard: FreeDashboardScreen()
            case .repairFailed: RepairFailedScreen(model: model)
            }
        }
        .id(model.step)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
    }

    // MARK: Footer

    private var footer: some View {
        OnboardingGlassGroup(spacing: 8) {
            ZStack {
                PageDots(count: model.navigator.pageSteps.count, index: model.navigator.pageIndex)
                HStack(spacing: 8) {
                    leadingButtons
                    Spacer(minLength: 12)
                    trailingButtons
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }

    /// Back, or what closes the window when there is nothing to go back to.
    private var backTitle: String {
        if model.navigator.canGoBack { return "Back" }
        return model.mode == .repair ? "Cancel" : "Not Now"
    }

    @ViewBuilder
    private var leadingButtons: some View {
        switch model.step {
        case .welcome:
            Button("Not Now") { model.closeTapped() }
                .onboardingSecondary()
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.notNow")
        case .protection, .license, .freeDashboard:
            Button(backTitle) { model.backTapped() }
                .onboardingSecondary()
                .keyboardShortcut(model.navigator.canGoBack ? nil : .cancelAction)
                .accessibilityIdentifier("onboarding.back")
        case .approve:
            approveSecondaryButton
        case .done:
            if model.mode != .repair && !license.canEnableProtection {
                Button("Enter License Key…") { model.enterLicenseTapped() }
                    .onboardingSecondary()
            }
        case .repairFailed:
            Button("Open System Settings") { model.openLoginItems() }
                .onboardingSecondary()
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
        switch model.step {
        case .welcome, .protection:
            Button("Continue") { model.continueTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.continue")
        case .license:
            if license.canEnableProtection {
                Button("Continue") { model.continueTapped() }
                    .onboardingPrimary()
            } else {
                Button("Skip for Now") { model.continueTapped() }
                    .onboardingSecondary()
                    .accessibilityIdentifier("onboarding.skipLicense")
            }
        case .approve:
            approvePrimaryButton
        case .done, .freeDashboard:
            Button("Open Dashboard") { model.openDashboardTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.openDashboard")
        case .repairFailed:
            Button("Done") { model.closeTapped() }
                .onboardingPrimary()
        }
    }

    @ViewBuilder
    private var approveSecondaryButton: some View {
        switch model.tracker.secondaryAction {
        case .back:
            Button(backTitle) { model.approveSecondaryTapped() }
                .onboardingSecondary()
                .keyboardShortcut(model.navigator.canGoBack ? nil : .cancelAction)
                .accessibilityIdentifier("onboarding.back")
        case .cancel:
            Button("Cancel") { model.approveSecondaryTapped() }
                .onboardingSecondary()
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.cancel")
        case .openSystemSettings:
            Button("Open System Settings") { model.approveSecondaryTapped() }
                .onboardingSecondary()
        case .none:
            Button(backTitle) {}
                .onboardingSecondary()
                .disabled(true)
        }
    }

    @ViewBuilder
    private var approvePrimaryButton: some View {
        switch model.tracker.primaryAction {
        case .approveHelper:
            Button("Approve Helper") { model.approvePrimaryTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.approve")
                .accessibilityHint("Registers the helper. macOS then asks you to turn it on.")
        case .openSystemSettings:
            Button("Open System Settings") { model.approvePrimaryTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.openSystemSettings")
        case .tryAgain:
            Button("Try Again") { model.approvePrimaryTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.tryAgain")
        case .checking:
            Button("Approve Helper") {}
                .onboardingPrimary()
                .disabled(true)
        }
    }
}

// MARK: - Buttons

private extension View {
    /// The screen's one primary action: prominent Liquid Glass on macOS 26,
    /// the bordered prominent style before it.
    @ViewBuilder
    func onboardingPrimary() -> some View {
        let base = self.controlSize(.large).keyboardShortcut(.defaultAction)
        if #available(macOS 26, *) {
            base.buttonStyle(.glassProminent)
        } else {
            base.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func onboardingSecondary() -> some View {
        let base = self.controlSize(.large)
        if #available(macOS 26, *) {
            base.buttonStyle(.glass)
        } else {
            base.buttonStyle(.bordered)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int?

    var body: some View {
        if count > 0, let index {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? Color.primary : Color.secondary.opacity(dot < index ? 0.7 : 0.35))
                        .frame(width: 7, height: 7)
                        .scaleEffect(dot == index ? 1.15 : 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(count)")
        }
    }
}

private struct RepairBadge: View {
    var body: some View {
        Text("Repair")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .modifier(TintedCapsule())
            .accessibilityLabel("Repair")
    }
}

private struct TintedCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(Color.accentColor.opacity(0.25)), in: Capsule())
        } else {
            content.background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Screens

private struct ScreenTitle: View {
    let title: String
    var subtitle: String?
    var large = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(large ? .largeTitle : .title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 410)
            }
        }
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
    }
}

private struct LargeAppIcon: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 92, height: 92)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

private struct WelcomeScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            LargeAppIcon()
                .padding(.top, 18)
            ScreenTitle(title: OnboardingCopy.welcomeTitle, subtitle: OnboardingCopy.welcomeLine, large: true)
                .padding(.top, 22)
            Label(OnboardingCopy.welcomeReassurance, systemImage: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .padding(.top, 18)
            Spacer(minLength: 16)
            Caption(OnboardingCopy.crashReportCaption)
                .padding(.bottom, 6)
        }
    }
}

private struct ProtectionScreen: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(title: OnboardingCopy.protectionTitle, subtitle: OnboardingCopy.protectionBody)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Compare", selection: Binding(
                    get: { model.showsProtectionIllustration },
                    set: { newValue in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.36)) {
                            model.selectIllustration(showsProtection: newValue)
                        }
                    }
                )) {
                    Text("AWDL active").tag(false)
                    Text("Ping Protection on").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                LatencyIllustration(showsProtection: model.showsProtectionIllustration)

                HStack {
                    Text("Ping, last 30 seconds")
                    Spacer()
                    if model.showsProtectionIllustration {
                        Text("Steady").fontWeight(.semibold).foregroundColor(.primary) + Text(" near 25 ms")
                    } else {
                        Text("3 spikes").fontWeight(.semibold).foregroundColor(.primary) + Text(" over 100 ms")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: 444)
            .modifier(OnboardingCardBackground())
            .padding(.top, 18)

            Spacer(minLength: 16)
            Caption(OnboardingCopy.protectionCaption)
                .padding(.bottom, 6)
        }
    }
}

private struct LicenseScreen: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(title: OnboardingCopy.licenseTitle, subtitle: OnboardingCopy.licenseBody)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                if license.canEnableProtection {
                    Label("License active", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    HStack(spacing: 8) {
                        TextField("License Key", text: $model.licenseKey,
                                  prompt: Text("Paste your key from the Gumroad receipt"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit { model.activateLicense() }
                            .accessibilityLabel("License Key")
                        Button {
                            model.activateLicense()
                        } label: {
                            if license.isVerifying {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Activate")
                            }
                        }
                        .disabled(license.isVerifying
                                  || model.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ping Protection, $15")
                            .font(.headline)
                        Text("One purchase, no subscription.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Buy a License…") { model.buyLicense() }
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .modifier(OnboardingCardBackground())
                }

                if let message = model.licenseMessage {
                    Label(message, systemImage: model.licenseMessageIsError
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(model.licenseMessageIsError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 380)
            .padding(.top, 20)

            Spacer(minLength: 16)
            Caption(OnboardingCopy.licenseDonorNote)
                .padding(.bottom, 6)
        }
    }
}

private struct ApproveScreen: View {
    @ObservedObject var model: OnboardingModel

    private var tracker: HelperApprovalTracker { model.tracker }

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(
                title: OnboardingCopy.approveTitle(mode: model.mode),
                subtitle: OnboardingCopy.approveSubtitle(mode: model.mode)
            )
            .padding(.top, 6)

            OnboardingGlassGroup(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ApprovalPreviewCard(caption: OnboardingCopy.cardCaptions[0], state: tracker.cards[0]) {
                        NotificationBannerArt()
                    }
                    .frame(width: 118)
                    ApprovalPreviewCard(caption: OnboardingCopy.cardCaptions[1], state: tracker.cards[1]) {
                        SwitchSectionArt(
                            sectionName: tracker.variant.backgroundSectionName,
                            animatesHint: tracker.animatesSwitchHint,
                            isApproved: tracker.cards[1] == .complete
                        )
                    }
                    .frame(maxWidth: .infinity)
                    ApprovalPreviewCard(caption: OnboardingCopy.cardCaptions[2], state: tracker.cards[2]) {
                        AuthenticationSheetArt()
                    }
                    .frame(width: 118)
                }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What macOS will show")

            Breadcrumb(levels: SystemSettingsCopy.switchBreadcrumb(osMajorVersion: Self.osMajorVersion(for: tracker.variant)))
                .padding(.top, 12)

            ApprovalStatusView(line: tracker.statusLine)
                .frame(minHeight: 56)
                .padding(.top, 10)

            Spacer(minLength: 10)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                (Text(OnboardingCopy.trustLine) + Text(" "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .frame(maxWidth: 410, alignment: .leading)
            Button("More about the helper") { model.showsHelperInfo = true }
                .buttonStyle(.link)
                .font(.caption)
                .frame(maxWidth: 410, alignment: .leading)
                .padding(.leading, 24)
                .padding(.bottom, 4)
                .popover(isPresented: $model.showsHelperInfo, arrowEdge: .top) {
                    HelperFactsView { model.showsHelperInfo = false }
                }
        }
    }

    /// The breadcrumb follows the tracker's variant so previews can show
    /// each macOS layout.
    private static func osMajorVersion(for variant: SystemSettingsCopy.Variant) -> Int {
        switch variant {
        case .loginItems: return 14
        case .loginItemsAndExtensions: return 15
        case .appBackgroundActivity: return 26
        }
    }
}

private struct Breadcrumb: View {
    let levels: [String]

    var body: some View {
        levels.enumerated().reduce(Text("")) { text, item in
            let level = item.offset == 0
                ? Text(item.element).fontWeight(.semibold).foregroundColor(.primary)
                : Text(item.element)
            return item.offset == 0 ? text + level : text + Text("  ›  ").foregroundColor(Color(nsColor: .tertiaryLabelColor)) + level
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 440)
        .accessibilityLabel(levels.joined(separator: ", "))
    }
}

private struct ApprovalStatusView: View {
    let line: HelperApprovalTracker.StatusLine

    var body: some View {
        VStack(spacing: 3) {
            if let title = line.title {
                HStack(spacing: 8) {
                    switch line.tone {
                    case .progress:
                        ProgressView().controlSize(.small)
                    case .success:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .warning:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .neutral:
                        EmptyView()
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                }
            }
            Text(line.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var titleColor: Color {
        switch line.tone {
        case .success: return .green
        case .warning: return .orange
        case .neutral, .progress: return .primary
        }
    }
}

private struct HelperFactsView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the helper does")
                .font(.headline)
            ForEach(OnboardingCopy.helperFacts, id: \.self) { fact in
                Label {
                    Text(fact).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark").foregroundStyle(.green)
                }
            }
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

private struct DoneScreen: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared

    private var copy: OnboardingCopy.Done {
        if model.mode == .repair, let report = model.repairReport,
           report.title != RepairResultCopy.successTitle {
            // The helper answers, but the current protection change or its
            // restoration did not finish. Say exactly that.
            return OnboardingCopy.Done(title: report.title, body: report.message, isComplete: false)
        }
        return OnboardingCopy.done(
            mode: model.mode,
            protectionOn: model.protectionOnAtDone,
            canEnableProtection: license.canEnableProtection
        )
    }

    var body: some View {
        let copy = copy
        VStack(spacing: 0) {
            DrawnStatusMark(kind: copy.isComplete ? .success : .attention)
                .padding(.top, 26)
            ScreenTitle(title: copy.title, subtitle: copy.body, large: true)
                .padding(.top, 20)
            MenuBarHint(protectionOn: model.protectionOnAtDone)
                .padding(.top, 20)
            Spacer(minLength: 16)
        }
    }
}

private struct FreeDashboardScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            LargeAppIcon()
                .padding(.top, 18)
            ScreenTitle(title: OnboardingCopy.freeDashboardTitle, subtitle: OnboardingCopy.freeDashboardBody, large: true)
                .padding(.top, 22)
            Spacer(minLength: 16)
        }
    }
}

private struct RepairFailedScreen: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            DrawnStatusMark(kind: .failure)
                .padding(.top, 26)
            ScreenTitle(
                title: OnboardingCopy.repairFailedTitle,
                subtitle: model.repairReport?.message ?? RepairResultCopy.failureMessage
            )
            .padding(.top, 20)
            Spacer(minLength: 16)
        }
    }
}

// MARK: - Previews

#if DEBUG
extension OnboardingModel {
    /// Fixed states for previews and the `--onboarding-preview=` launch
    /// argument in Debug builds.
    static func previewModel(named name: String) -> OnboardingModel? {
        let modern = SystemSettingsCopy.variant
        func tracker(_ status: HelperRegistrationState, start: Bool = false, at now: TimeInterval = 0,
                     opened: Bool = false, repair: Bool = false) -> HelperApprovalTracker {
            var value = HelperApprovalTracker(status: repair ? .enabled : status, variant: modern, needsNewRegistration: repair)
            if start {
                value.start(now: 0)
                value.update(status: status, now: now, monitorOpenedLoginItems: opened)
            }
            return value
        }
        let ready = tracker(.notRegistered)
        switch name {
        case "welcome":
            return OnboardingModel(preview: .firstRun, step: .welcome, tracker: ready, canEnableProtection: true)
        case "protection":
            return OnboardingModel(preview: .firstRun, step: .protection, tracker: ready, canEnableProtection: true)
        case "license":
            return OnboardingModel(preview: .firstRun, step: .license, tracker: ready, canEnableProtection: false)
        case "approve":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: ready, canEnableProtection: true)
        case "approve-earlier":
            return OnboardingModel(preview: .finishSetup, step: .approve, tracker: tracker(.requiresApproval), canEnableProtection: true)
        case "approve-waiting":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: tracker(.requiresApproval, start: true, at: 4), canEnableProtection: true)
        case "approve-handoff":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: tracker(.requiresApproval, start: true, at: 12, opened: true), canEnableProtection: true)
        case "approve-late":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: tracker(.requiresApproval, start: true, at: 47, opened: true), canEnableProtection: true)
        case "approve-timeout":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: tracker(.requiresApproval, start: true, at: 61, opened: true), canEnableProtection: true)
        case "approve-approved":
            return OnboardingModel(preview: .firstRun, step: .approve, tracker: tracker(.enabled, start: true, at: 20), canEnableProtection: true)
        case "done":
            return OnboardingModel(preview: .firstRun, step: .done, tracker: tracker(.enabled), canEnableProtection: true, protectionOn: true)
        case "done-unlicensed":
            return OnboardingModel(preview: .firstRun, step: .done, tracker: tracker(.enabled), canEnableProtection: false)
        case "free-dashboard":
            return OnboardingModel(preview: .firstRun, step: .freeDashboard, tracker: ready, canEnableProtection: false)
        case "repair":
            return OnboardingModel(preview: .repair, step: .approve, tracker: tracker(.enabled, repair: true), canEnableProtection: true)
        case "repair-done":
            return OnboardingModel(preview: .repair, step: .done, tracker: tracker(.enabled), canEnableProtection: true, protectionOn: true,
                                   repairReport: HelperTestReport(title: RepairResultCopy.successTitle, message: RepairResultCopy.successMessage(protectionOn: true)))
        case "repair-failed":
            return OnboardingModel(preview: .repair, step: .repairFailed, tracker: tracker(.enabled), canEnableProtection: true,
                                   repairReport: HelperTestReport(title: RepairResultCopy.failureTitle, message: RepairResultCopy.failureMessage))
        default:
            return nil
        }
    }

    static let previewNames = [
        "welcome", "protection", "license", "approve", "approve-earlier", "approve-waiting", "approve-handoff",
        "approve-late", "approve-timeout", "approve-approved", "done", "done-unlicensed", "free-dashboard",
        "repair", "repair-done", "repair-failed",
    ]
}

#Preview("Welcome") {
    OnboardingView(model: OnboardingModel.previewModel(named: "welcome")!)
        .frame(width: 540, height: 600)
}

#Preview("Approve, waiting") {
    OnboardingView(model: OnboardingModel.previewModel(named: "approve-waiting")!)
        .frame(width: 540, height: 600)
}

#Preview("Repair") {
    OnboardingView(model: OnboardingModel.previewModel(named: "repair")!)
        .frame(width: 540, height: 600)
        .preferredColorScheme(.dark)
}
#endif
