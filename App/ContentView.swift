import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: QuotaDashboardViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    quotaPreview
                    appearancePanel
                    statusPanel
                }
                .padding(32)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Codex 剩余额度")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("宿主 App 会读取本机 Codex 会话数据，把最新快照写进 App Group，Widget 只消费这份共享 JSON。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            Button(action: viewModel.refresh) {
                Text("手动刷新")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private var quotaPreview: some View {
        HStack(spacing: 22) {
            PreviewRingCard(
                title: "5小时",
                percent: viewModel.snapshot.fiveHourRemainingPercent,
                backgroundOpacity: viewModel.widgetBackgroundOpacity,
                backgroundStyle: viewModel.widgetBackgroundStyle,
                backgroundColor: viewModel.widgetBackgroundColor,
                refreshText: previewRefreshText(
                    resetAt: viewModel.snapshot.fiveHourResetAt,
                    style: .fiveHour
                )
            )

            PreviewRingCard(
                title: "1周",
                percent: viewModel.snapshot.weekRemainingPercent,
                backgroundOpacity: viewModel.widgetBackgroundOpacity,
                backgroundStyle: viewModel.widgetBackgroundStyle,
                backgroundColor: viewModel.widgetBackgroundColor,
                refreshText: previewRefreshText(
                    resetAt: viewModel.snapshot.weekResetAt,
                    style: .week
                )
            )
        }
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("背景设置")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(Int(viewModel.widgetBackgroundOpacity * 100))%")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Slider(
                value: Binding(
                    get: { viewModel.widgetBackgroundOpacity },
                    set: { viewModel.setWidgetBackgroundOpacity($0) }
                ),
                in: 0.08...0.70
            )
            .tint(.white)

            HStack(spacing: 14) {
                Button {
                    viewModel.setWidgetBackgroundStyle(.defaultColor)
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(previewGradient(for: nil, opacity: 0.42))
                            .frame(width: 44, height: 28)

                        Text("默认颜色")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                viewModel.widgetBackgroundStyle == .defaultColor
                                    ? Color.white.opacity(0.12)
                                    : Color.white.opacity(0.05)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                viewModel.widgetBackgroundStyle == .defaultColor
                                    ? Color.white.opacity(0.24)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)

                ColorPicker(
                    "自定义颜色",
                    selection: Binding(
                        get: { color(from: viewModel.widgetBackgroundColor) },
                        set: { newColor in
                            if let customColor = widgetBackgroundColor(from: newColor) {
                                viewModel.setWidgetBackgroundColor(customColor)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(previewGradient(for: viewModel.widgetBackgroundColor, opacity: 0.42))
                        .frame(width: 44, height: 28)

                    Text("自定义颜色")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            viewModel.widgetBackgroundStyle == .custom
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.05)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            viewModel.widgetBackgroundStyle == .custom
                                ? Color.white.opacity(0.24)
                                : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow("快照状态", viewModel.snapshot.state.rawValue)
            statusRow("快照时间", viewModel.snapshot.snapshotAt.formatted(date: .abbreviated, time: .standard))
            statusRow("最近刷新", viewModel.lastRefreshDate?.formatted(date: .abbreviated, time: .standard) ?? "--")
            statusRow("套餐类型", viewModel.snapshot.planType ?? "--")
            statusRow("Rollout 文件", viewModel.snapshot.sourceRolloutPath ?? "暂无数据")
            statusRow("共享 JSON", viewModel.sharedStorePath ?? "App Group 尚未可用")

            if let lastErrorMessage = viewModel.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.98, green: 0.51, blue: 0.46))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 82, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewRefreshText(resetAt: Date?, style: QuotaRefreshStyle) -> String {
        guard let resetAt,
              let percent = style == .fiveHour
                ? viewModel.snapshot.fiveHourRemainingPercent
                : viewModel.snapshot.weekRemainingPercent
        else {
            return "暂无数据"
        }

        return QuotaRefreshFormatter.displayText(
            for: QuotaRingSnapshot(label: "", remainingPercent: percent, resetAt: resetAt),
            style: style,
            now: Date(),
            locale: Locale(identifier: "zh_Hans_CN"),
            timeZone: .current
        )
    }

    private func previewGradient(for color: WidgetBackgroundColor?, opacity: Double) -> LinearGradient {
        let colors = widgetBackgroundColors(for: color, opacity: opacity)
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func widgetBackgroundColors(for backgroundColor: WidgetBackgroundColor?, opacity: Double) -> [Color] {
        let baseColor = backgroundColor ?? WidgetBackgroundColor(red: 0.74, green: 0.76, blue: 0.82)
        let shadowColor = WidgetBackgroundColor(
            red: max(0, baseColor.red * 0.72),
            green: max(0, baseColor.green * 0.72),
            blue: max(0, baseColor.blue * 0.72)
        )

        return [
            color(from: baseColor).opacity(opacity),
            color(from: shadowColor).opacity(max(0.06, opacity - 0.06)),
        ]
    }

    private func color(from widgetColor: WidgetBackgroundColor) -> Color {
        Color(
            .sRGB,
            red: widgetColor.red,
            green: widgetColor.green,
            blue: widgetColor.blue,
            opacity: 1
        )
    }

    private func widgetBackgroundColor(from color: Color) -> WidgetBackgroundColor? {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB)
        guard let nsColor else {
            return nil
        }

        return WidgetBackgroundColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent)
        )
    }
}

private struct PreviewRingCard: View {
    let title: String
    let percent: Int?
    let backgroundOpacity: Double
    let backgroundStyle: WidgetBackgroundStyle
    let backgroundColor: WidgetBackgroundColor
    let refreshText: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                PreviewSegmentedRingView(
                    percent: percent,
                    segments: 34,
                    lineWidth: 12
                )

                Text(percent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -4)

                Text(refreshText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
                    .offset(y: 28)
            }
            .frame(width: 154, height: 154)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var backgroundColors: [Color] {
        let baseColor: WidgetBackgroundColor

        switch backgroundStyle {
        case .defaultColor:
            baseColor = WidgetBackgroundColor(red: 0.74, green: 0.76, blue: 0.82)
        case .custom:
            baseColor = backgroundColor
        }

        let shadowColor = WidgetBackgroundColor(
            red: max(0, baseColor.red * 0.72),
            green: max(0, baseColor.green * 0.72),
            blue: max(0, baseColor.blue * 0.72)
        )

        return [
            Color(.sRGB, red: baseColor.red, green: baseColor.green, blue: baseColor.blue, opacity: backgroundOpacity),
            Color(.sRGB, red: shadowColor.red, green: shadowColor.green, blue: shadowColor.blue, opacity: max(0.06, backgroundOpacity - 0.06)),
        ]
    }
}

private struct PreviewSegmentedRingView: View {
    let percent: Int?
    let segments: Int
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2 - lineWidth / 2
            let filledCount = Int((Double(percent ?? 0) / 100) * Double(segments))
            let segmentLength = max(10, radius * 0.22)
            let step = 360 / Double(segments)

            ZStack {
                ForEach(0..<segments, id: \.self) { index in
                    let angle = 90 + Double(index) * step
                    let radians = angle * .pi / 180

                    Capsule(style: .circular)
                        .fill(segmentColor(index: index, filledCount: filledCount))
                        .frame(width: segmentLength, height: lineWidth)
                        .rotationEffect(.degrees(angle + 90))
                        .position(
                            x: geometry.size.width / 2 + CGFloat(cos(radians)) * radius,
                            y: geometry.size.height / 2 + CGFloat(sin(radians)) * radius
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func segmentColor(index: Int, filledCount: Int) -> Color {
        guard index < filledCount else {
            return Color.white.opacity(0.08)
        }

        let normalized = Double(index) / Double(max(1, segments - 1))
        return Color(hue: 0.33 * normalized, saturation: 0.92, brightness: 0.98)
    }
}
