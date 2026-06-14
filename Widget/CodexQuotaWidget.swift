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
        VStack(spacing: 7) {
            HStack(spacing: 22) {
                ring(
                    title: "5小时",
                    percent: entry.snapshot.fiveHourRemainingPercent
                )

                ring(
                    title: "1周",
                    percent: entry.snapshot.weekRemainingPercent
                )
            }

            VStack(spacing: 5) {
                timeProgressRow(style: .fiveHour, resetAt: entry.snapshot.fiveHourResetAt)
                timeProgressRow(style: .week, resetAt: entry.snapshot.weekResetAt)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private func ring(
        title: String,
        percent: Int?
    ) -> some View {
        ZStack {
            SegmentedRingView(
                percent: percent,
                segments: 34,
                lineWidth: 7,
                size: 92
            )

            VStack(spacing: 3) {
                Text(percent.map { "\($0)%" } ?? "--")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .frame(width: 104, height: 92)
        .frame(maxWidth: .infinity)
    }

    private func timeProgressRow(style: QuotaRefreshStyle, resetAt: Date?) -> some View {
        let progress = remainingWindowProgress(style: style, resetAt: resetAt)
        let leading = resetAt == nil ? "--" : timeLabel(for: entry.date, style: style)
        let trailing = resetAt.map { timeLabel(for: $0, style: style) } ?? "--"

        return HStack(spacing: 8) {
            Text(leading)
                .frame(width: 50, alignment: .trailing)

            SegmentedBarView(
                progress: progress,
                segments: 24,
                size: CGSize(width: 166, height: 8)
            )

            Text(trailing)
                .frame(width: 50, alignment: .leading)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.88))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

    private func timeLabel(for date: Date, style: QuotaRefreshStyle) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = .current

        switch style {
        case .fiveHour:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "M月d日"
        }

        return formatter.string(from: date)
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

private struct SegmentedBarView: View {
    let progress: Double?
    let segments: Int
    let size: CGSize

    var body: some View {
        FullColorWidgetImage(
            nsImage: SegmentedBarRenderer.image(
                progress: progress,
                segments: segments,
                size: size
            ),
            size: size
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
        FullColorWidgetImage(nsImage: nsImage, size: CGSize(width: size, height: size))
    }
}

private enum SegmentedBarRenderer {
    static func image(
        progress: Double?,
        segments: Int,
        size: CGSize
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.clear(CGRect(origin: .zero, size: size))

        let gap: CGFloat = 4
        let segmentWidth = (size.width - CGFloat(max(0, segments - 1)) * gap) / CGFloat(segments)
        let filledCount = Int((min(max(progress ?? 0, 0), 1) * Double(segments)).rounded())

        for index in 0..<segments {
            let rect = CGRect(
                x: CGFloat(index) * (segmentWidth + gap),
                y: 0,
                width: segmentWidth,
                height: size.height
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: size.height / 2,
                cornerHeight: size.height / 2,
                transform: nil
            )

            context.setFillColor(GaugeSegmentPalette.color(index: index, filledCount: filledCount, segments: segments))
            context.addPath(path)
            context.fillPath()
        }

        return image
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

            context.setFillColor(GaugeSegmentPalette.color(index: index, filledCount: filledCount, segments: segments))
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        return image
    }
}

private enum GaugeSegmentPalette {
    static func color(index: Int, filledCount: Int, segments: Int) -> CGColor {
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
