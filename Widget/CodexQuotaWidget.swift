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
    }
}

private struct CodexQuotaWidgetView: View {
    let entry: CodexQuotaWidgetEntry

    var body: some View {
        let backgroundOpacity = min(0.70, max(0.08, entry.snapshot.widgetBackgroundOpacity ?? 0.18))
        let backgroundStyle = entry.snapshot.widgetBackgroundStyle ?? .defaultColor
        let backgroundColor = entry.snapshot.widgetBackgroundColor

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
            LinearGradient(
                colors: backgroundColors(
                    for: backgroundStyle,
                    customColor: backgroundColor,
                    opacity: backgroundOpacity
                ),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                    lineWidth: 8
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

    private func backgroundColors(
        for style: WidgetBackgroundStyle,
        customColor: WidgetBackgroundColor?,
        opacity: Double
    ) -> [Color] {
        let baseColor: WidgetBackgroundColor

        switch style {
        case .defaultColor:
            baseColor = WidgetBackgroundColor(red: 0.74, green: 0.76, blue: 0.82)
        case .custom:
            baseColor = customColor ?? WidgetBackgroundColor(red: 0.74, green: 0.76, blue: 0.82)
        }

        let shadowColor = WidgetBackgroundColor(
            red: max(0, baseColor.red * 0.72),
            green: max(0, baseColor.green * 0.72),
            blue: max(0, baseColor.blue * 0.72)
        )

        return [
            Color(.sRGB, red: baseColor.red, green: baseColor.green, blue: baseColor.blue, opacity: opacity),
            Color(.sRGB, red: shadowColor.red, green: shadowColor.green, blue: shadowColor.blue, opacity: max(0.06, opacity - 0.06)),
        ]
    }
}

private struct SegmentedRingView: View {
    let percent: Int?
    let segments: Int
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2 - lineWidth / 2
            let filledCount = Int((Double(percent ?? 0) / 100) * Double(segments))
            let segmentLength = max(6, radius * 0.18)
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
            return Color.white.opacity(0.09)
        }

        let normalized = Double(index) / Double(max(1, segments - 1))
        return Color(hue: 0.33 * normalized, saturation: 0.92, brightness: 0.98)
    }
}
