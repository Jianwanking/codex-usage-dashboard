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
                refreshText: previewRefreshText(
                    resetAt: viewModel.snapshot.fiveHourResetAt,
                    style: .fiveHour
                )
            )

            PreviewRingCard(
                title: "1周",
                percent: viewModel.snapshot.weekRemainingPercent,
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
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
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
