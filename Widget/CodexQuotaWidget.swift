import AppKit
import SwiftUI
import WidgetKit

struct CodexQuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CodexQuotaSnapshot
}

struct CodexQuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexQuotaWidgetEntry {
        CodexQuotaWidgetEntry(
            date: Date(),
            snapshot: sampleSnapshot
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexQuotaWidgetEntry) -> Void) {
        completion(
            CodexQuotaWidgetEntry(
                date: Date(),
                snapshot: loadSharedSnapshot()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexQuotaWidgetEntry>) -> Void) {
        let entry = CodexQuotaWidgetEntry(
            date: Date(),
            snapshot: loadSharedSnapshot()
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: entry.date) ?? entry.date.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSharedSnapshot() -> CodexQuotaSnapshot {
        var stores: [SharedSnapshotStore] = []

        if let appGroupStore = SharedSnapshotStore.appGroupStore(
            groupIdentifier: CodexQuotaAppConfig.appGroupIdentifier,
            fileName: CodexQuotaAppConfig.snapshotFileName
        ) {
            stores.append(appGroupStore)
        }

        stores.append(
            SharedSnapshotStore.appContainerFallbackStore(
                bundleIdentifier: CodexQuotaAppConfig.widgetExtensionBundleIdentifier,
                fileName: CodexQuotaAppConfig.snapshotFileName
            )
        )
        stores.append(
            SharedSnapshotStore.localFallbackStore(
                fileName: CodexQuotaAppConfig.snapshotFileName
            )
        )

        return SharedSnapshotStore.newestOKSnapshot(from: stores) ?? .fullQuotaFallback(at: Date())
    }

    private var sampleSnapshot: CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            state: .ok,
            fiveHourRemainingPercent: 95,
            fiveHourResetAt: Calendar.current.date(byAdding: .hour, value: 5, to: Date()),
            weekRemainingPercent: 85,
            weekResetAt: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
            snapshotAt: Date(),
            planType: "plus",
            sourceRolloutPath: nil,
            widgetBackgroundOpacity: 0.18,
            widgetBackgroundStyle: .defaultColor,
            widgetBackgroundColor: nil
        )
    }
}

struct CodexQuotaWidget: Widget {
    private let kind = "CodexQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexQuotaWidgetProvider()) { entry in
            CodexQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 剩余额度")
        .description("显示 5 小时和 1 周额度的剩余比例与刷新时间。")
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(true)
        .contentMarginsDisabled()
    }
}

private struct CodexQuotaWidgetView: View {
    let entry: CodexQuotaWidgetEntry

    var body: some View {
        GeometryReader { proxy in
            let spacing = min(max(proxy.size.width * 0.04, 10), 18)
            let verticalInset: CGFloat = 6
            let titleHeight: CGFloat = 16
            let ringTitleGap: CGFloat = 0
            let cellWidth = max(0, (proxy.size.width - spacing) / 2)
            let ringSize = max(0, min(cellWidth, proxy.size.height - verticalInset * 2 - titleHeight - ringTitleGap, 136))

            HStack(spacing: spacing) {
                gauge(
                    title: "5小时",
                    percent: entry.snapshot.fiveHourRemainingPercent,
                    resetAt: entry.snapshot.fiveHourResetAt,
                    style: .fiveHour,
                    ringSize: ringSize,
                    titleHeight: titleHeight,
                    ringTitleGap: ringTitleGap
                )
                .frame(width: cellWidth, height: proxy.size.height)

                gauge(
                    title: "1周",
                    percent: entry.snapshot.weekRemainingPercent,
                    resetAt: entry.snapshot.weekResetAt,
                    style: .week,
                    ringSize: ringSize,
                    titleHeight: titleHeight,
                    ringTitleGap: ringTitleGap
                )
                .frame(width: cellWidth, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private func gauge(
        title: String,
        percent: Int?,
        resetAt: Date?,
        style: QuotaRefreshStyle,
        ringSize: CGFloat,
        titleHeight: CGFloat,
        ringTitleGap: CGFloat
    ) -> some View {
        let percentFontSize: CGFloat = 30
        let refreshFontSize: CGFloat = 12.5
        let titleFontSize: CGFloat = 14

        return VStack(spacing: ringTitleGap) {
            ZStack {
                DoubleSegmentedRingView(
                    quotaPercent: percent,
                    timeProgress: remainingWindowProgress(style: style, resetAt: resetAt),
                    segments: 36,
                    size: ringSize,
                    outerRadius: 61.788,
                    innerRadius: 49.0
                )

                Text(entry.snapshot.isFullQuotaFallback ? "??" : (percent.map { "\($0)%" } ?? "--"))
                    .font(.system(size: percentFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: ringSize * 0.62, height: ringSize * 0.30)
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)
                    .offset(y: -ringSize * 0.035)

                Text(refreshText(percent: percent, resetAt: resetAt, style: style))
                    .font(.system(size: refreshFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .frame(width: ringSize * 0.62, height: ringSize * 0.14)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
                    .offset(y: ringSize * 0.18)
            }
            .frame(width: ringSize, height: ringSize)

            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.66))
                .frame(width: ringSize * 0.58, height: titleHeight)
                .lineLimit(1)
                .offset(y: -1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remainingWindowProgress(style: QuotaRefreshStyle, resetAt: Date?) -> Double? {
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

        let remaining = resetAt.timeIntervalSince(entry.date)
        return min(max(remaining / duration, 0), 1)
    }

    private func refreshText(percent: Int?, resetAt: Date?, style: QuotaRefreshStyle) -> String {
        if entry.snapshot.isFullQuotaFallback {
            return ""
        }

        guard let percent, let resetAt else {
            return "暂无数据"
        }

        return QuotaRefreshFormatter.displayText(
            for: QuotaRingSnapshot(label: "", remainingPercent: percent, resetAt: resetAt),
            style: style,
            now: entry.date,
            locale: Locale(identifier: "zh_Hans_CN"),
            timeZone: .current
        )
    }

}

private struct FullColorWidgetImage: View {
    let nsImage: NSImage
    let size: CGSize

    var body: some View {
        let image = Image(nsImage: nsImage)

        if #available(macOS 15.0, *) {
            image
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size.width, height: size.height)
        } else {
            image
                .frame(width: size.width, height: size.height)
        }
    }
}

private struct DoubleSegmentedRingView: View {
    let quotaPercent: Int?
    let timeProgress: Double?
    let segments: Int
    let size: CGFloat
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    var body: some View {
        let nsImage = SegmentedRingRenderer.image(
            quotaProgress: quotaPercent.map { Double($0) / 100 },
            timeProgress: timeProgress,
            segments: segments,
            size: size,
            outerRadius: outerRadius,
            innerRadius: innerRadius
        )
        FullColorWidgetImage(nsImage: nsImage, size: CGSize(width: size, height: size))
    }
}

private enum SegmentedRingRenderer {
    static func image(
        quotaProgress: Double?,
        timeProgress: Double?,
        segments: Int,
        size: CGFloat,
        outerRadius: CGFloat,
        innerRadius: CGFloat
    ) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.clear(CGRect(x: 0, y: 0, width: size, height: size))

        drawRing(
            in: context,
            progress: quotaProgress,
            segments: segments,
            blockSize: 8.0,
            blockRadius: 1.8,
            radius: outerRadius,
            size: size,
            palette: .gauge
        )
        drawRing(
            in: context,
            progress: timeProgress,
            segments: segments,
            blockSize: 5.6,
            blockRadius: 1.3,
            radius: innerRadius,
            size: size,
            palette: .monochrome
        )

        return image
    }

    private static func drawRing(
        in context: CGContext,
        progress: Double?,
        segments: Int,
        blockSize: CGFloat,
        blockRadius: CGFloat,
        radius: CGFloat,
        size: CGFloat,
        palette: GaugeSegmentPalette
    ) {
        let filledCount = Int((min(max(progress ?? 0, 0), 1) * Double(segments)).rounded())
        let step = 360 / Double(segments)

        for index in 0..<segments {
            let angle = 90 + Double(index) * step
            let radians = angle * .pi / 180
            let center = CGPoint(
                x: size / 2 + CGFloat(cos(radians)) * radius,
                y: size / 2 - CGFloat(sin(radians)) * radius
            )

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(-(angle + 90) * .pi / 180))

            let rect = CGRect(
                x: -blockSize / 2,
                y: -blockSize / 2,
                width: blockSize,
                height: blockSize
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: blockRadius,
                cornerHeight: blockRadius,
                transform: nil
            )

            context.setFillColor(palette.color(index: index, filledCount: filledCount, segments: segments))
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
    }
}

private enum GaugeSegmentPalette {
    case gauge
    case monochrome

    func color(index: Int, filledCount: Int, segments: Int) -> CGColor {
        guard index < filledCount else {
            return CGColor(gray: 1, alpha: 0.09)
        }

        switch self {
        case .gauge:
            let normalized = Double(index) / Double(max(1, segments - 1))
            return NSColor(
                hue: CGFloat(0.33 * normalized),
                saturation: 0.92,
                brightness: 0.98,
                alpha: 1
            ).cgColor
        case .monochrome:
            return NSColor(
                red: 0.72,
                green: 0.86,
                blue: 0.90,
                alpha: 0.85
            ).cgColor
        }
    }
}
