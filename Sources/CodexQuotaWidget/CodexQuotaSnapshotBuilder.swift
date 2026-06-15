import Foundation

public enum CodexQuotaSnapshotBuilder {
    public static func build(
        fromRolloutPaths rolloutPaths: [URL],
        now: Date = Date()
    ) throws -> CodexQuotaSnapshot {
        for rolloutPath in rolloutPaths {
            if let snapshot = try snapshot(from: rolloutPath, now: now) {
                return snapshot
            }
        }

        return .unavailable(at: now)
    }

    public static func buildFromLocalCodexState(
        stateDatabaseURL: URL = CodexQuotaPaths.defaultStateDatabaseURL,
        now: Date = Date(),
        limit: Int = 20
    ) throws -> CodexQuotaSnapshot {
        let rolloutPaths = try SQLiteThreadPathProvider(databasePath: stateDatabaseURL)
            .recentRolloutPaths(limit: limit)
        return try build(fromRolloutPaths: rolloutPaths, now: now)
    }

    private static func snapshot(from rolloutPath: URL, now: Date) throws -> CodexQuotaSnapshot? {
        guard let event = try latestTokenCountEvent(in: rolloutPath) else {
            return nil
        }

        var fiveHourQuota: QuotaValue?
        var weekQuota: QuotaValue?

        for quota in [event.primary, event.secondary].compactMap({ $0 }) {
            switch quota.windowMinutes {
            case 300:
                fiveHourQuota = quota
            case 10080:
                weekQuota = quota
            default:
                continue
            }
        }

        guard let fiveHourQuota, let weekQuota else {
            return nil
        }

        return CodexQuotaSnapshot(
            state: .ok,
            fiveHourRemainingPercent: remainingPercent(fromUsedPercent: fiveHourQuota.usedPercent),
            fiveHourResetAt: Date(timeIntervalSince1970: TimeInterval(fiveHourQuota.resetAt)),
            weekRemainingPercent: remainingPercent(fromUsedPercent: weekQuota.usedPercent),
            weekResetAt: Date(timeIntervalSince1970: TimeInterval(weekQuota.resetAt)),
            snapshotAt: now,
            planType: event.planType,
            sourceRolloutPath: rolloutPath.path
        )
    }

    private static func latestTokenCountEvent(in rolloutPath: URL) throws -> TokenCountEvent? {
        guard FileManager.default.fileExists(atPath: rolloutPath.path) else {
            return nil
        }

        let contents = try String(contentsOf: rolloutPath, encoding: .utf8)
        var latestEvent: TokenCountEvent?
        var latestOverallEvent: TokenCountEvent?

        contents.enumerateLines { line, _ in
            guard let event = parseTokenCountEvent(from: line) else {
                return
            }
            latestEvent = event
            if event.limitID == "codex" {
                latestOverallEvent = event
            }
        }

        return latestOverallEvent ?? latestEvent
    }

    private static func parseTokenCountEvent(from line: String) -> TokenCountEvent? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String,
              type == "event_msg",
              let payload = root["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        return TokenCountEvent(
            primary: parseQuotaValue(from: rateLimits["primary"]),
            secondary: parseQuotaValue(from: rateLimits["secondary"]),
            planType: rateLimits["plan_type"] as? String,
            limitID: rateLimits["limit_id"] as? String
        )
    }

    private static func parseQuotaValue(from rawValue: Any?) -> QuotaValue? {
        guard let rawValue = rawValue as? [String: Any],
              let usedPercent = rawValue["used_percent"] as? Double,
              let windowMinutes = rawValue["window_minutes"] as? Int,
              let resetAt = rawValue["resets_at"] as? Int
        else {
            return nil
        }

        return QuotaValue(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }

    private static func remainingPercent(fromUsedPercent usedPercent: Double) -> Int {
        max(0, min(100, Int((100.0 - usedPercent).rounded())))
    }
}

private struct TokenCountEvent {
    let primary: QuotaValue?
    let secondary: QuotaValue?
    let planType: String?
    let limitID: String?
}

private struct QuotaValue {
    let usedPercent: Double
    let windowMinutes: Int
    let resetAt: Int
}
