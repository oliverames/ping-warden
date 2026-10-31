// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import SwiftUI

// MARK: - Layout scale

/// One spacing scale for every screen, so gaps read as related or separate
/// at a glance: 4 inside a label pair, 8 between a title and its line, 16
/// between items, 24 between groups.
enum OnboardingSpacing {
    static let tight: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let gutter: CGFloat = 40
    /// The readable column for body text and cards.
    static let column: CGFloat = 420
}

// MARK: - Window content

/// The setup window: the first-run Welcome (the 4.3 layout), the guided
/// steps that follow it, Finish Setup, and Repair's approval step. Each
/// guided screen centers its content vertically between the title bar and
/// the button row, so no screen strands content at the top or bottom.
struct OnboardingView: View {
    /// The window is 540 points wide and as tall as the current screen's
    /// content, so no screen carries a band of empty space. Shorter screens
    /// keep a floor height so the window does not jump between steps. The
    /// floor fits Approve, the tallest step, so the footer buttons stay
    /// under the pointer from Protection through Done. On a display too
    /// short for a screen, the window stops at the display's visible height
    /// and the screen scrolls (PING-WARDEN-D, #144).
    static let width: CGFloat = 540
    static let minimumContentHeight: CGFloat = 420
    /// Accessibility text sizes scroll inside a window of this height.
    static let accessibilityHeight: CGFloat = 680

    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The window measures this view and sizes itself, no taller than its
        // display. A screen that doesn't fit scrolls rather than asking the
        // window to grow past the display, which looped AppKit's layout.
        ViewThatFits(in: .vertical) {
            sizedContent
            ScrollView { sizedContent }
        }
        .background(.background)
        .overlay(alignment: .topTrailing) {
            if model.mode == .repair {
                // Level with the window controls in the transparent title
                // bar: both centered 16 points from the top.
                RepairBadge()
                    .padding(.top, 6)
                    .padding(.trailing, 18)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.step)
    }

    /// The current screen at its own height, or the accessibility height.
    private var sizedContent: some View {
        Group {
            if model.step == .welcome {
                WelcomeScreen(model: model)
            } else {
                VStack(spacing: 0) {
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView { steppedContent }
                    } else {
                        steppedContent
                    }
                    footer
                }
            }
        }
        .frame(width: Self.width)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? Self.accessibilityHeight : nil)
        .fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
    }

    /// The current screen, centered in at least the floor height.
    private var steppedContent: some View {
        screen
            .padding(.horizontal, OnboardingSpacing.gutter)
            .padding(.top, OnboardingSpacing.small)
            .padding(.bottom, OnboardingSpacing.large)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Self.minimumContentHeight)
    }

    @ViewBuilder
    private var screen: some View {
        Group {
            switch model.step {
            case .welcome: EmptyView()
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
        .padding(.horizontal, OnboardingSpacing.large)
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
            EmptyView()
        case .protection, .license, .freeDashboard:
            Button(backTitle) { model.backTapped() }
                .onboardingSecondary()
                .keyboardShortcut(model.navigator.canGoBack ? nil : .cancelAction)
                .accessibilityIdentifier("onboarding.back")
        case .approve:
            approveSecondaryButton
        case .done:
            EmptyView()
        case .repairFailed:
            Button("Open System Settings") { model.openLoginItems() }
                .onboardingSecondary()
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
        switch model.step {
        case .welcome:
            EmptyView()
        case .protection:
            Button("Continue") { model.continueTapped() }
                .onboardingPrimary()
                .accessibilityIdentifier("onboarding.continue")
        case .license:
            if model.canEnableProtection {
                Button("Continue") { model.continueTapped() }
                    .onboardingPrimary()
                    .accessibilityIdentifier("onboarding.continue")
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
        VStack(spacing: OnboardingSpacing.small) {
            Text(title)
                .font(large ? .largeTitle : .title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: OnboardingSpacing.column)
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
            .frame(maxWidth: OnboardingSpacing.column)
    }
}

private struct LargeAppIcon: View {
    var size: CGFloat = 80

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The 4.3 Welcome, kept as people know it: icon, title, tagline, three
/// feature rows, then the setup action area and the crash-report note.
/// The guided steps start from its setup button.
private struct WelcomeScreen: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            welcomeContent
                .padding(.horizontal, OnboardingSpacing.gutter)
                .padding(.top, OnboardingSpacing.medium)
                .frame(maxWidth: .infinity)
            actionArea
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: OnboardingSpacing.large) {
            VStack(spacing: 12) {
                LargeAppIcon()
                Text(OnboardingCopy.welcomeTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(OnboardingCopy.welcomeLine)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                ForEach(OnboardingCopy.welcomeBenefits, id: \.title) { benefit in
                    WelcomeBenefitRow(benefit: benefit)
                }
            }
            .frame(maxWidth: 400)
        }
    }

    /// The setup action area, as in 4.3: one line about what setup asks
    /// for, the primary action, Not Now, and the crash-report note.
    private var actionArea: some View {
        VStack(spacing: 14) {
            Text(model.canEnableProtection
                 ? "Setup asks for one approval in \(SystemSettingsCopy.loginItemsPaneName)."
                 : OnboardingCopy.welcomeUnlicensedLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            OnboardingGlassGroup(spacing: 12) {
                VStack(spacing: 12) {
                    if model.canEnableProtection {
                        welcomeButton("Turn On Ping Protection", prominent: true) { model.continueTapped() }
                            .accessibilityIdentifier("onboarding.continue")
                    } else {
                        // Without a license, the free dashboard leads and
                        // setup starts with the license.
                        welcomeButton("Open Dashboard", prominent: true) { model.openDashboardTapped() }
                            .accessibilityIdentifier("onboarding.openDashboard")
                        welcomeButton("Set Up Ping Protection", prominent: false) { model.continueTapped() }
                            .accessibilityIdentifier("onboarding.continue")
                    }
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 240)

            Button("Not Now") { model.closeTapped() }
                .buttonStyle(.link)
                .font(.callout)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("onboarding.notNow")

            Caption(OnboardingCopy.crashReportCaption)
        }
        .padding(.horizontal, OnboardingSpacing.gutter)
        .padding(.top, OnboardingSpacing.small)
        .padding(.bottom, OnboardingSpacing.large)
    }

    @ViewBuilder
    private func welcomeButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Text(title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        if prominent {
            button.onboardingPrimary()
        } else {
            button.onboardingSecondary()
        }
    }
}

private struct WelcomeBenefitRow: View {
    let benefit: OnboardingCopy.Benefit

    var body: some View {
        HStack(alignment: .top, spacing: OnboardingSpacing.medium) {
            Image(systemName: benefit.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OnboardingSpacing.tight) {
                Text(benefit.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(benefit.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProtectionScreen: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            ScreenTitle(title: OnboardingCopy.protectionTitle, subtitle: OnboardingCopy.protectionBody)

            VStack(alignment: .leading, spacing: OnboardingSpacing.small) {
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
            .padding(OnboardingSpacing.medium)
            .frame(maxWidth: OnboardingSpacing.column)
            .modifier(OnboardingCardBackground())

            Caption(OnboardingCopy.protectionCaption)
        }
    }
}

/// The license field, Activate, and the purchase option share one card,
/// with the donor note directly beneath it.
private struct LicenseScreen: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            ScreenTitle(title: OnboardingCopy.licenseTitle, subtitle: OnboardingCopy.licenseBody)

            VStack(alignment: .leading, spacing: OnboardingSpacing.medium) {
                if model.canEnableProtection {
                    // Green symbol, plain text, like Settings → License.
                    Label {
                        Text("License active")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                } else {
                    keyEntry
                    Divider()
                    purchaseRow
                }
            }
            .padding(OnboardingSpacing.medium)
            .frame(maxWidth: OnboardingSpacing.column)
            .modifier(OnboardingCardBackground())

            Caption(OnboardingCopy.licenseDonorNote)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: OnboardingSpacing.small) {
            Text("License key")
                .font(.headline)
                .accessibilityHidden(true)
            HStack(spacing: OnboardingSpacing.small) {
                TextField("License Key", text: $model.licenseKey, prompt: Text(OnboardingCopy.licenseFieldPrompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .autocorrectionDisabled()
                    .onSubmit { model.activateLicense() }
                    .accessibilityLabel("License Key")
                // Regular size, the license field's height.
                Button {
                    model.activateLicense()
                } label: {
                    BusyButtonLabel(title: "Activate", isBusy: license.isVerifying)
                }
                .disabled(license.isVerifying
                          || model.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("onboarding.activate")
            }
            if let message = model.licenseMessage {
                Label(message, systemImage: model.licenseMessageIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(model.licenseMessageIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var purchaseRow: some View {
        HStack(alignment: .center, spacing: OnboardingSpacing.medium) {
            VStack(alignment: .leading, spacing: OnboardingSpacing.tight) {
                Text("Ping Protection, $15")
                    .font(.headline)
                Text("One purchase, no subscription.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: OnboardingSpacing.small)
            Button("Buy a License…") { model.buyLicense() }
        }
    }
}

private struct ApproveScreen: View {
    @ObservedObject var model: OnboardingModel

    private var tracker: HelperApprovalTracker { model.tracker }

    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            ScreenTitle(
                title: OnboardingCopy.approveTitle(mode: model.mode),
                subtitle: OnboardingCopy.approveSubtitle(mode: model.mode)
            )

            VStack(spacing: OnboardingSpacing.medium) {
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
                .accessibilityElement(children: .contain)
                .accessibilityLabel("What macOS will show")

                Breadcrumb(levels: SystemSettingsCopy.switchBreadcrumb(osMajorVersion: Self.osMajorVersion(for: tracker.variant)))
            }

            // Tall enough for a title over two lines of detail, so the
            // window keeps its height as the status changes.
            ApprovalStatusView(line: tracker.statusLine)
                .frame(minHeight: 50)

            TrustCaption(showsHelperInfo: $model.showsHelperInfo)
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

/// The lock, one sentence, and an inline "More about the helper" link in the
/// same caption style, wrapping as one paragraph beside the lock.
private struct TrustCaption: View {
    @Binding var showsHelperInfo: Bool

    private static let infoURL = URL(string: "pingwarden-onboarding://helper-info")!

    private var caption: AttributedString {
        var text = AttributedString(OnboardingCopy.trustLine + " ")
        var link = AttributedString("More about the helper")
        link.link = Self.infoURL
        text.append(link)
        return text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnboardingSpacing.small) {
            Image(systemName: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Hugs its wrapped lines, so the 400-point frame centers the
            // lock and text together like everything else on the screen.
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 400)
        .environment(\.openURL, OpenURLAction { url in
            guard url == Self.infoURL else { return .systemAction }
            showsHelperInfo = true
            return .handled
        })
        .popover(isPresented: $showsHelperInfo, arrowEdge: .top) {
            HelperFactsView { showsHelperInfo = false }
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
        VStack(spacing: OnboardingSpacing.tight) {
            if let title = line.title {
                HStack(spacing: OnboardingSpacing.small) {
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
                    // The symbol carries the color; colored headline text
                    // was low contrast in light mode.
                    Text(title)
                        .font(.headline)
                }
            }
            Text(line.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: OnboardingSpacing.column)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
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
            canEnableProtection: model.canEnableProtection
        )
    }

    var body: some View {
        let copy = copy
        VStack(spacing: OnboardingSpacing.large) {
            DrawnStatusMark(kind: copy.isComplete ? .success : .attention)
            ScreenTitle(title: copy.title, subtitle: copy.body, large: true)
            MenuBarHint(protectionOn: model.protectionOnAtDone)
        }
    }
}

private struct FreeDashboardScreen: View {
    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            LargeAppIcon(size: 92)
            ScreenTitle(title: OnboardingCopy.freeDashboardTitle, subtitle: OnboardingCopy.freeDashboardBody, large: true)
        }
    }
}

private struct RepairFailedScreen: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: OnboardingSpacing.large) {
            DrawnStatusMark(kind: .failure)
            ScreenTitle(
                title: OnboardingCopy.repairFailedTitle,
                subtitle: model.repairReport?.message ?? RepairResultCopy.failureMessage,
                large: true
            )
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
            return OnboardingModel(preview: .firstRun, step: .welcome, tracker: ready, canEnableProtection: false)
        case "welcome-licensed":
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
        "welcome", "welcome-licensed", "protection", "license", "approve", "approve-earlier", "approve-waiting", "approve-handoff",
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
