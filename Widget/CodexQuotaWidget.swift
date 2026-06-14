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
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSharedSnapshot() -> CodexQuotaSnapshot {
        if let appGroupStore = SharedSnapshotStore.appGroupStore(
            groupIdentifier: CodexQuotaAppConfig.appGroupIdentifier,
            fileName: CodexQuotaAppConfig.snapshotFileName
        ) {
            do {
                return try appGroupStore.load()
            } catch {
            }
        }

        let fallbackStore = SharedSnapshotStore.localFallbackStore(
            fileName: CodexQuotaAppConfig.snapshotFileName
        )

        guard let snapshot = try? fallbackStore.load() else {
            return .unavailable(at: Date())
        }

        return snapshot
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
    }
}

private struct CodexQuotaWidgetView: View {
    let entry: CodexQuotaWidgetEntry

    var body: some View {
        HStack(spacing: 18) {
            ring(
                title: "5小时",
                percent: entry.snapshot.fiveHourRemainingPercent,
                resetAt: entry.snapshot.fiveHourResetAt,
                style: .fiveHour
            )

            ring(
                title: "1周",
                percent: entry.snapshot.weekRemainingPercent,
                resetAt: entry.snapshot.weekResetAt,
                style: .week
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private func ring(
        title: String,
        percent: Int?,
        resetAt: Date?,
        style: QuotaRefreshStyle
    ) -> some View {
        VStack(spacing: 5) {
            ZStack {
                DoubleSegmentedRingView(
                    quotaPercent: percent,
                    timeProgress: remainingWindowProgress(style: style, resetAt: resetAt),
                    segments: 34,
                    size: 116
                )

                VStack(spacing: 4) {
                    Text(percent.map { "\($0)%" } ?? "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(refreshText(percent: percent, resetAt: resetAt, style: style))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.64))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 116, height: 116)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
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

    var body: some View {
        let nsImage = SegmentedRingRenderer.image(
            quotaProgress: quotaPercent.map { Double($0) / 100 },
            timeProgress: timeProgress,
            segments: segments,
            size: size
        )
        FullColorWidgetImage(nsImage: nsImage, size: CGSize(width: size, height: size))
    }
}

private enum SegmentedRingRenderer {
    static func image(
        quotaProgress: Double?,
        timeProgress: Double?,
        segments: Int,
        size: CGFloat
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
            lineWidth: 8,
            radius: size / 2 - 4,
            size: size,
            palette: .gauge
        )
        drawRing(
            in: context,
            progress: timeProgress,
            segments: segments,
            lineWidth: 7,
            radius: size / 2 - 22,
            size: size,
            palette: .monochrome
        )

        return image
    }

    private static func drawRing(
        in context: CGContext,
        progress: Double?,
        segments: Int,
        lineWidth: CGFloat,
        radius: CGFloat,
        size: CGFloat,
        palette: GaugeSegmentPalette
    ) {
        let filledCount = Int((min(max(progress ?? 0, 0), 1) * Double(segments)).rounded())
        let segmentLength = max(6, radius * 0.18)
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
                x: -segmentLength / 2,
                y: -lineWidth / 2,
                width: segmentLength,
                height: lineWidth
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: lineWidth / 2,
                cornerHeight: lineWidth / 2,
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
            let normalized = Double(index) / Double(max(1, filledCount - 1))
            return NSColor(
                calibratedWhite: CGFloat(0.58 + 0.26 * normalized),
                alpha: 0.82
            ).cgColor
        }
    }
}
