import Foundation

public enum CodexQuotaSnapshotBuilder {
    public static func build(
        fromRolloutPaths rolloutPaths: [URL],
        now: Date = Date()
    ) throws -> CodexQuotaSnapshot {
        var bestOverallCandidate: SnapshotCandidate?
        var bestFallbackCandidate: SnapshotCandidate?

        for (index, rolloutPath) in rolloutPaths.enumerated() {
            let events = try latestTokenCountEvents(in: rolloutPath)
            if let overallEvent = events.overall,
               let snapshot = snapshot(from: overallEvent, sourceURL: rolloutPath, now: now) {
                let candidate = SnapshotCandidate(snapshot: snapshot, timestamp: overallEvent.timestamp, pathIndex: index)
                if isNewer(candidate, than: bestOverallCandidate) {
                    bestOverallCandidate = candidate
                }
            }
            if let fallbackEvent = events.fallback,
               let snapshot = snapshot(from: fallbackEvent, sourceURL: rolloutPath, now: now) {
                let candidate = SnapshotCandidate(snapshot: snapshot, timestamp: fallbackEvent.timestamp, pathIndex: index)
                if isNewer(candidate, than: bestFallbackCandidate) {
                    bestFallbackCandidate = candidate
                }
            }
        }

        return bestOverallCandidate?.snapshot ?? bestFallbackCandidate?.snapshot ?? .unavailable(at: now)
    }

    public static func buildFromLocalCodexState(
        stateDatabaseURL: URL = CodexQuotaPaths.defaultStateDatabaseURL,
        logsDatabaseURL: URL = CodexQuotaPaths.defaultLogsDatabaseURL,
        now: Date = Date(),
        limit: Int = 20
    ) throws -> CodexQuotaSnapshot {
        var candidates: [CodexQuotaSnapshot] = []

        if let logsSnapshot = try? buildFromCodexLogs(
            logDatabaseURL: logsDatabaseURL,
            now: now,
            limit: 300
        ) {
            candidates.append(logsSnapshot)
        }

        let rolloutPaths = try SQLiteThreadPathProvider(databasePath: stateDatabaseURL)
            .recentRolloutPaths(limit: limit)
        let rolloutSnapshot = try build(fromRolloutPaths: rolloutPaths, now: now)
        if rolloutSnapshot.state == .ok {
            candidates.append(rolloutSnapshot)
        }

        return candidates.max { lhs, rhs in
            lhs.freshnessDate < rhs.freshnessDate
        } ?? .unavailable(at: now)
    }

    public static func buildFromCodexLogs(
        logDatabaseURL: URL = CodexQuotaPaths.defaultLogsDatabaseURL,
        now: Date = Date(),
        limit: Int = 50
    ) throws -> CodexQuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: logDatabaseURL.path) else {
            return nil
        }

        let logRows = try SQLiteCodexLogProvider(databasePath: logDatabaseURL)
            .recentRateLimitLogRows(limit: limit)

        for logRow in logRows {
            guard let event = parseRateLimitLogEvent(from: logRow),
                  let snapshot = snapshot(from: event, sourceURL: logDatabaseURL, now: now)
            else {
                continue
            }

            return snapshot
        }

        return nil
    }

    private static func snapshot(from event: TokenCountEvent, sourceURL: URL, now: Date) -> CodexQuotaSnapshot? {
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
            sourceRolloutPath: sourceURL.path,
            sourceEventAt: event.timestamp
        )
    }

    private static func latestTokenCountEvents(in rolloutPath: URL) throws -> TokenCountEvents {
        guard FileManager.default.fileExists(atPath: rolloutPath.path) else {
            return TokenCountEvents(overall: nil, fallback: nil)
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

        return TokenCountEvents(overall: latestOverallEvent, fallback: latestEvent)
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
            timestamp: parseTimestamp(from: root["timestamp"] as? String),
            limitID: rateLimits["limit_id"] as? String
        )
    }

    private static func parseRateLimitLogEvent(from logRow: CodexLogRow) -> TokenCountEvent? {
        switch logRow.target {
        case "codex_client::default_client":
            return parseHTTPHeaderRateLimitEvent(from: logRow)
        case "codex_api::endpoint::responses_websocket":
            return parseWebSocketRateLimitEvent(from: logRow)
        default:
            return nil
        }
    }

    private static func parseHTTPHeaderRateLimitEvent(from logRow: CodexLogRow) -> TokenCountEvent? {
        guard let data = jsonObjectData(in: logRow.body, after: "headers="),
              let headers = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return TokenCountEvent(
            primary: parseHeaderQuotaValue(
                from: headers,
                prefix: "x-codex-primary",
                windowKey: "x-codex-primary-window-minutes",
                resetKey: "x-codex-primary-reset-at"
            ),
            secondary: parseHeaderQuotaValue(
                from: headers,
                prefix: "x-codex-secondary",
                windowKey: "x-codex-secondary-window-minutes",
                resetKey: "x-codex-secondary-reset-at"
            ),
            planType: headers["x-codex-plan-type"] as? String,
            timestamp: logRow.eventDate,
            limitID: "codex"
        )
    }

    private static func parseWebSocketRateLimitEvent(from logRow: CodexLogRow) -> TokenCountEvent? {
        guard let data = jsonObjectData(in: logRow.body, after: "websocket event: "),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String,
              type == "codex.rate_limits",
              let rateLimits = root["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        return TokenCountEvent(
            primary: parseLogQuotaValue(from: rateLimits["primary"]),
            secondary: parseLogQuotaValue(from: rateLimits["secondary"]),
            planType: root["plan_type"] as? String,
            timestamp: logRow.eventDate,
            limitID: "codex"
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

    private static func parseLogQuotaValue(from rawValue: Any?) -> QuotaValue? {
        guard let rawValue = rawValue as? [String: Any],
              let usedPercent = doubleValue(rawValue["used_percent"]),
              let windowMinutes = intValue(rawValue["window_minutes"]),
              let resetAt = intValue(rawValue["reset_at"])
        else {
            return nil
        }

        return QuotaValue(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }

    private static func parseHeaderQuotaValue(
        from headers: [String: Any],
        prefix: String,
        windowKey: String,
        resetKey: String
    ) -> QuotaValue? {
        guard let usedPercent = doubleValue(headers["\(prefix)-used-percent"]),
              let windowMinutes = intValue(headers[windowKey]),
              let resetAt = intValue(headers[resetKey])
        else {
            return nil
        }

        return QuotaValue(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }

    private static func doubleValue(_ rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }
        if let value = rawValue as? Int {
            return Double(value)
        }
        if let value = rawValue as? String {
            return Double(value)
        }
        return nil
    }

    private static func intValue(_ rawValue: Any?) -> Int? {
        if let value = rawValue as? Int {
            return value
        }
        if let value = rawValue as? Double {
            return Int(value)
        }
        if let value = rawValue as? String {
            return Int(value)
        }
        return nil
    }

    private static func jsonObjectData(in text: String, after marker: String) -> Data? {
        guard let markerRange = text.range(of: marker),
              let startIndex = text[markerRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var isInsideString = false
        var isEscaping = false

        var index = startIndex
        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[startIndex...index]).data(using: .utf8)
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func remainingPercent(fromUsedPercent usedPercent: Double) -> Int {
        max(0, min(100, Int((100.0 - usedPercent).rounded())))
    }

    private static func parseTimestamp(from rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: rawValue) {
            return date
        }

        return ISO8601DateFormatter().date(from: rawValue)
    }

    private static func isNewer(_ candidate: SnapshotCandidate, than current: SnapshotCandidate?) -> Bool {
        guard let current else {
            return true
        }

        switch (candidate.timestamp, current.timestamp) {
        case let (candidateTimestamp?, currentTimestamp?):
            return candidateTimestamp > currentTimestamp
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return candidate.pathIndex < current.pathIndex
        }
    }
}

private struct SnapshotCandidate {
    let snapshot: CodexQuotaSnapshot
    let timestamp: Date?
    let pathIndex: Int
}

private struct TokenCountEvents {
    let overall: TokenCountEvent?
    let fallback: TokenCountEvent?
}

private struct TokenCountEvent {
    let primary: QuotaValue?
    let secondary: QuotaValue?
    let planType: String?
    let timestamp: Date?
    let limitID: String?
}

private struct QuotaValue {
    let usedPercent: Double
    let windowMinutes: Int
    let resetAt: Int
}

private extension CodexLogRow {
    var eventDate: Date {
        Date(
            timeIntervalSince1970: TimeInterval(timestampSeconds)
                + TimeInterval(timestampNanoseconds) / 1_000_000_000
        )
    }
}
