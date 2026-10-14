// Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.

import SwiftUI

// Illustrations for the setup window, drawn in SwiftUI rather than shipped
// as screenshots: they follow light and dark appearance and the accent
// color, and each macOS variant is a string change instead of a new capture.
// They are stylized stand-ins for what macOS shows, so VoiceOver skips them;
// the captions beside them carry the meaning.

// MARK: - Shared surfaces

enum OnboardingMetrics {
    static let cardCornerRadius: CGFloat = 14
    static let largeCardCornerRadius: CGFloat = 16
}

/// The project's card surface: Liquid Glass on macOS 26, the regular
/// material before it. Matches the Dashboard's cards.
struct OnboardingCardBackground: ViewModifier {
    var cornerRadius: CGFloat = OnboardingMetrics.largeCardCornerRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

/// Groups glass shapes so they render together on macOS 26; a plain
/// container before it.
struct OnboardingGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

/// A small floating panel inside an illustration, standing in for a macOS
/// banner, settings group, or sheet.
private struct MiniPanel: ViewModifier {
    var cornerRadius: CGFloat = 10
    var shadow = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .shadow(color: .black.opacity(shadow ? 0.16 : 0), radius: 6, y: 3)
    }
}

/// A grey bar standing in for text the illustration does not spell out.
private struct Skeleton: View {
    var width: CGFloat?
    var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.55))
            .frame(width: width, height: height)
    }
}

private struct AppIconImage: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - Approve step cards

/// One preview card: an illustration with a caption. The current card is
/// outlined in the accent color; finished cards dim and gain a check mark.
struct ApprovalPreviewCard<Art: View>: View {
    let caption: String
    let state: HelperApprovalTracker.CardState
    @ViewBuilder var art: () -> Art

    var body: some View {
        VStack(spacing: 8) {
            // The check mark is part of the glass view's content: a sibling
            // drawn outside it would sit under the container's glass layer.
            ZStack(alignment: .topTrailing) {
                art()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(state == .complete ? 0.55 : (state == .upcoming ? 0.88 : 1))

                if state == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .font(.system(size: 18, weight: .semibold))
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .modifier(OnboardingCardBackground(cornerRadius: OnboardingMetrics.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: state == .current ? 1.5 : 0)
            )
            .background(
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius + 3, style: .continuous)
                    .fill(Color.accentColor.opacity(state == .current ? 0.22 : 0))
                    .padding(-3)
            )
            .accessibilityHidden(true)

            Text(caption)
                .font(.caption)
                .fontWeight(state == .current ? .semibold : .regular)
                .foregroundStyle(state == .current ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityValue(Self.accessibilityValue(for: state))
    }

    private static func accessibilityValue(for state: HelperApprovalTracker.CardState) -> String {
        switch state {
        case .upcoming: return "Not yet"
        case .current: return "Next step"
        case .complete: return "Done"
        }
    }
}

/// Card 1: the "Background Items Added" banner macOS posts after a fresh
/// registration. The banner's body text has no Apple source, so it stays a
/// skeleton.
struct NotificationBannerArt: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            AppIconImage(size: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("Background Items Added")
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Skeleton()
                Skeleton(width: 40)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .modifier(MiniPanel(cornerRadius: 11))
        .padding(.horizontal, 7)
    }
}

/// Card 2: the switch section with Ping Warden's row. While this is the
/// current step the switch shows the motion to make, unless Reduce Motion
/// is on.
struct SwitchSectionArt: View {
    let sectionName: String
    let animatesHint: Bool
    let isApproved: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sectionName.uppercased())
                .font(.system(size: 7, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 3)
            row { Skeleton(width: 50) } toggle: { MiniSwitch(isOn: true) }
            Divider()
            row {
                Text("Ping Warden")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } toggle: {
                hintSwitch
            } icon: {
                AppIconImage(size: 16)
            }
            .background(Color.accentColor.opacity(0.08))
            Divider()
            row { Skeleton(width: 38) } toggle: { MiniSwitch(isOn: false) }
        }
        .modifier(MiniPanel(cornerRadius: 10, shadow: false))
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var hintSwitch: some View {
        if isApproved {
            MiniSwitch(isOn: true)
        } else if animatesHint && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 1.4)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate / 1.4) % 2 == 1
                MiniSwitch(isOn: on)
                    .animation(.easeInOut(duration: 0.3), value: on)
            }
        } else {
            MiniSwitch(isOn: false)
                .overlay(
                    Capsule().strokeBorder(Color.accentColor, lineWidth: animatesHint ? 1.5 : 0)
                        .padding(-2)
                )
        }
    }

    private func row<Label: View, Toggle: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder toggle: () -> Toggle
    ) -> some View {
        row(label: label, toggle: toggle) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 16, height: 16)
        }
    }

    private func row<Label: View, Toggle: View, Icon: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder toggle: () -> Toggle,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 6) {
            icon()
            label()
            Spacer(minLength: 2)
            toggle()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// A miniature switch, green when on.
struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.green : Color(nsColor: .systemGray).opacity(0.45))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                .padding(1)
        }
        .frame(width: 26, height: 15)
    }
}

/// Card 3: the authentication sheet that confirms the change.
struct AuthenticationSheetArt: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "touchid")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.tint)
            Text("Use Touch ID or enter your password")
                .font(.system(size: 7.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Capsule().fill(Color(nsColor: .systemGray).opacity(0.3))
                Capsule().fill(Color.accentColor.opacity(0.85))
            }
            .frame(height: 9)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .modifier(MiniPanel(cornerRadius: 12))
        .padding(.horizontal, 9)
    }
}

// MARK: - Latency illustration

/// Illustrative ping samples over 30 seconds, not measurements: a steady
/// baseline near 25 ms, and the same baseline with three AWDL spikes.
enum LatencyIllustrationData {
    static let sampleCount = 40
    static let maximum: Double = 160

    static let protected: [Double] = {
        var seed: Int64 = 7
        func random() -> Double {
            seed = (seed * 16807) % 2147483647
            return Double(seed - 1) / 2147483646
        }
        return (0..<sampleCount).map { _ in 22 + random() * 5 }
    }()

    static let spikes: [Int] = [9, 21, 33]

    static let awdlActive: [Double] = {
        var values = protected
        for (index, value) in [(9, 128.0), (10, 74.0), (21, 152.0), (22, 66.0), (33, 118.0), (34, 52.0)] {
            values[index] = value
        }
        return values
    }()
}

private struct LatencyLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                y: rect.maxY - rect.height * CGFloat(min(value, LatencyIllustrationData.maximum) / LatencyIllustrationData.maximum)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Ping with AWDL active against Ping Protection on, on one scale.
struct LatencyIllustration: View {
    let showsProtection: Bool

    private let gridValues: [Double] = [0, 50, 100, 150]
    private let axisWidth: CGFloat = 26

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .topTrailing) {
                        ForEach(gridValues, id: \.self) { value in
                            Text("\(Int(value))")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .position(x: axisWidth / 2, y: y(for: value, height: geometry.size.height))
                        }
                    }
                }
                .frame(width: axisWidth)

                GeometryReader { geometry in
                    ZStack {
                        ForEach(gridValues, id: \.self) { value in
                            Path { path in
                                let lineY = y(for: value, height: geometry.size.height)
                                path.move(to: CGPoint(x: 0, y: lineY))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: lineY))
                            }
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                        LatencyLine(values: LatencyIllustrationData.awdlActive)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .opacity(showsProtection ? 0 : 1)
                        ForEach(LatencyIllustrationData.spikes, id: \.self) { index in
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6.5, height: 6.5)
                                .position(point(index: index, size: geometry.size))
                                .opacity(showsProtection ? 0 : 1)
                        }
                        LatencyLine(values: LatencyIllustrationData.protected)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .opacity(showsProtection ? 1 : 0)
                    }
                }
            }
            .frame(height: 104)

            HStack {
                Text("30 s ago")
                Spacer()
                Text("now")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(.leading, axisWidth + 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsProtection
            ? "Illustration of ping over 30 seconds with Ping Protection on. The line stays near 25 milliseconds."
            : "Illustration of ping over 30 seconds with AWDL active. Three spikes reach 120 to 150 milliseconds.")
    }

    private func y(for value: Double, height: CGFloat) -> CGFloat {
        height - height * CGFloat(value / LatencyIllustrationData.maximum)
    }

    private func point(index: Int, size: CGSize) -> CGPoint {
        let values = LatencyIllustrationData.awdlActive
        return CGPoint(
            x: size.width * CGFloat(index) / CGFloat(values.count - 1),
            y: y(for: values[index], height: size.height)
        )
    }
}

// MARK: - Done step

/// A filled circle whose check mark draws itself, or an X for a failure.
struct DrawnStatusMark: View {
    enum Kind {
        case success
        case attention
        case failure
    }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(fill)
            mark
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.easeOut(duration: 0.52).delay(0.16)) { progress = 1 }
            }
        }
    }

    private var fill: Color {
        switch kind {
        case .success: return .green
        case .attention: return .orange
        case .failure: return .red
        }
    }

    private var mark: Path {
        var path = Path()
        switch kind {
        case .success, .attention:
            path.move(to: CGPoint(x: 25, y: 43))
            path.addLine(to: CGPoint(x: 37, y: 55))
            path.addLine(to: CGPoint(x: 60, y: 29))
        case .failure:
            path.move(to: CGPoint(x: 29, y: 29))
            path.addLine(to: CGPoint(x: 55, y: 55))
            path.move(to: CGPoint(x: 55, y: 29))
            path.addLine(to: CGPoint(x: 29, y: 55))
        }
        return path
    }
}

/// A slice of the menu bar with Ping Warden's icon highlighted, so the
/// person knows where the app lives after setup.
struct MenuBarHint: View {
    let protectionOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: protectionOn
                  ? "antenna.radiowaves.left.and.right.slash"
                  : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.primary)
                .frame(width: 28, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                )
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(.caption)
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(OnboardingCardBackground(cornerRadius: 999))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu bar with the Ping Warden icon highlighted")
    }
}
