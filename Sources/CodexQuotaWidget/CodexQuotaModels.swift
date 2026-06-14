import Foundation

public enum SnapshotState: String, Codable, Sendable {
    case ok
    case unavailable
}

public enum WidgetBackgroundStyle: String, Codable, Sendable {
    case defaultColor
    case custom
}

public struct WidgetBackgroundColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct QuotaRingSnapshot: Codable, Equatable, Sendable {
    public let label: String
    public let remainingPercent: Int
    public let resetAt: Date

    public init(label: String, remainingPercent: Int, resetAt: Date) {
        self.label = label
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }
}

public struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    public let state: SnapshotState
    public let fiveHourRemainingPercent: Int?
    public let fiveHourResetAt: Date?
    public let weekRemainingPercent: Int?
    public let weekResetAt: Date?
    public let snapshotAt: Date
    public let planType: String?
    public let sourceRolloutPath: String?
    public let widgetBackgroundOpacity: Double?
    public let widgetBackgroundStyle: WidgetBackgroundStyle?
    public let widgetBackgroundColor: WidgetBackgroundColor?

    public init(
        state: SnapshotState,
        fiveHourRemainingPercent: Int?,
        fiveHourResetAt: Date?,
        weekRemainingPercent: Int?,
        weekResetAt: Date?,
        snapshotAt: Date,
        planType: String?,
        sourceRolloutPath: String?,
        widgetBackgroundOpacity: Double? = nil,
        widgetBackgroundStyle: WidgetBackgroundStyle? = nil,
        widgetBackgroundColor: WidgetBackgroundColor? = nil
    ) {
        self.state = state
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourResetAt = fiveHourResetAt
        self.weekRemainingPercent = weekRemainingPercent
        self.weekResetAt = weekResetAt
        self.snapshotAt = snapshotAt
        self.planType = planType
        self.sourceRolloutPath = sourceRolloutPath
        self.widgetBackgroundOpacity = widgetBackgroundOpacity
        self.widgetBackgroundStyle = widgetBackgroundStyle
        self.widgetBackgroundColor = widgetBackgroundColor
    }

    public static func unavailable(at snapshotAt: Date) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            state: .unavailable,
            fiveHourRemainingPercent: nil,
            fiveHourResetAt: nil,
            weekRemainingPercent: nil,
            weekResetAt: nil,
            snapshotAt: snapshotAt,
            planType: nil,
            sourceRolloutPath: nil,
            widgetBackgroundOpacity: nil,
            widgetBackgroundStyle: nil,
            widgetBackgroundColor: nil
        )
    }

    public func withWidgetAppearance(
        opacity: Double,
        style: WidgetBackgroundStyle,
        color: WidgetBackgroundColor?
    ) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            state: state,
            fiveHourRemainingPercent: fiveHourRemainingPercent,
            fiveHourResetAt: fiveHourResetAt,
            weekRemainingPercent: weekRemainingPercent,
            weekResetAt: weekResetAt,
            snapshotAt: snapshotAt,
            planType: planType,
            sourceRolloutPath: sourceRolloutPath,
            widgetBackgroundOpacity: opacity,
            widgetBackgroundStyle: style,
            widgetBackgroundColor: color
        )
    }
}

public enum QuotaRefreshStyle: Sendable {
    case fiveHour
    case week
}
