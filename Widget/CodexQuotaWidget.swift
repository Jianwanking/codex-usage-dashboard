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
        .padding(.vertical, 16)
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
        VStack(spacing: 6) {
            ZStack {
                SegmentedRingView(
                    percent: percent,
                    segments: 34,
                    lineWidth: 8,
                    size: 118
                )

                Text(percent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .offset(y: -3)

                Text(refreshText(percent: percent, resetAt: resetAt, style: style))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .offset(y: 24)
            }
            .frame(width: 118, height: 118)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct SegmentedRingView: View {
    let percent: Int?
    let segments: Int
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        let nsImage = SegmentedRingRenderer.image(
            percent: percent,
            segments: segments,
            lineWidth: lineWidth,
            size: size
        )
        let image = Image(nsImage: nsImage)

        if #available(macOS 15.0, *) {
            image
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size, height: size)
        } else {
            image
                .frame(width: size, height: size)
        }
    }
}

private enum SegmentedRingRenderer {
    static func image(
        percent: Int?,
        segments: Int,
        lineWidth: CGFloat,
        size: CGFloat
    ) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.clear(CGRect(x: 0, y: 0, width: size, height: size))

        let radius = size / 2 - lineWidth / 2
        let filledCount = Int((Double(percent ?? 0) / 100) * Double(segments))
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

            context.setFillColor(segmentColor(index: index, filledCount: filledCount, segments: segments))
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        return image
    }

    private static func segmentColor(index: Int, filledCount: Int, segments: Int) -> CGColor {
        guard index < filledCount else {
            return CGColor(gray: 1, alpha: 0.09)
        }

        let normalized = Double(index) / Double(max(1, segments - 1))
        return NSColor(
            hue: CGFloat(0.33 * normalized),
            saturation: 0.92,
            brightness: 0.98,
            alpha: 1
        ).cgColor
    }
}
