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

                Text("当前 Widget 背景已切到 macOS 原生桌面玻璃样式，系统会接管背景呈现，不再做自定义颜色和透明度。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
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
                resetAt: viewModel.snapshot.fiveHourResetAt,
                style: .fiveHour,
                refreshText: previewRefreshText(
                    resetAt: viewModel.snapshot.fiveHourResetAt,
                    style: .fiveHour
                )
            )

            PreviewRingCard(
                title: "1周",
                percent: viewModel.snapshot.weekRemainingPercent,
                resetAt: viewModel.snapshot.weekResetAt,
                style: .week,
                refreshText: previewRefreshText(
                    resetAt: viewModel.snapshot.weekResetAt,
                    style: .week
                )
            )
        }
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

}

private struct PreviewRingCard: View {
    let title: String
    let percent: Int?
    let resetAt: Date?
    let style: QuotaRefreshStyle
    let refreshText: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                PreviewDoubleSegmentedRingView(
                    quotaPercent: percent,
                    timeProgress: remainingWindowProgress,
                    segments: 36
                )

                Text(percent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)
                    .frame(width: 92, height: 42)
                    .offset(y: -5)

                Text(refreshText)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
                    .frame(width: 92, height: 20)
                    .offset(y: 30)
            }
            .frame(width: 166, height: 166)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .offset(y: -1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var remainingWindowProgress: Double? {
        guard let resetAt else {
            return nil
        }

        let duration: TimeInterval
        switch style {
        case .fiveHour:
            duration = 300 * 60
        case .week:
            duration = 10_080 * 60
        }

        let remaining = resetAt.timeIntervalSince(Date())
        return min(max(remaining / duration, 0), 1)
    }
}

private struct PreviewDoubleSegmentedRingView: View {
    let quotaPercent: Int?
    let timeProgress: Double?
    let segments: Int

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 136
            let outerRadius = 61.788 * scale
            let innerRadius = 49.0 * scale

            ZStack {
                ring(
                    progress: quotaPercent.map { Double($0) / 100 },
                    radius: outerRadius,
                    blockSize: 8.0 * scale,
                    blockRadius: 1.8 * scale,
                    palette: .gauge,
                    geometry: geometry
                )

                ring(
                    progress: timeProgress,
                    radius: innerRadius,
                    blockSize: 5.6 * scale,
                    blockRadius: 1.3 * scale,
                    palette: .monochrome,
                    geometry: geometry
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func ring(
        progress: Double?,
        radius: CGFloat,
        blockSize: CGFloat,
        blockRadius: CGFloat,
        palette: PreviewSegmentPalette,
        geometry: GeometryProxy
    ) -> some View {
        let filledCount = Int((min(max(progress ?? 0, 0), 1) * Double(segments)).rounded())
        let step = 360 / Double(segments)

        return ZStack {
            ForEach(0..<segments, id: \.self) { index in
                let angle = 90 + Double(index) * step
                let radians = angle * .pi / 180

                RoundedRectangle(cornerRadius: blockRadius, style: .continuous)
                    .fill(palette.color(index: index, filledCount: filledCount, segments: segments))
                    .frame(width: blockSize, height: blockSize)
                    .rotationEffect(.degrees(angle + 90))
                    .position(
                        x: geometry.size.width / 2 + CGFloat(cos(radians)) * radius,
                        y: geometry.size.height / 2 - CGFloat(sin(radians)) * radius
                    )
            }
        }
    }
}

private enum PreviewSegmentPalette {
    case gauge
    case monochrome

    func color(index: Int, filledCount: Int, segments: Int) -> Color {
        guard index < filledCount else {
            return Color.white.opacity(0.09)
        }

        switch self {
        case .gauge:
            let normalized = Double(index) / Double(max(1, segments - 1))
            return Color(hue: 0.33 * normalized, saturation: 0.92, brightness: 0.98)
        case .monochrome:
            return Color(red: 0.72, green: 0.86, blue: 0.90).opacity(0.85)
        }
    }
}
