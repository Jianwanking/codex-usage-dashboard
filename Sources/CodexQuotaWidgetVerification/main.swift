import Foundation
import CodexQuotaWidget

@main
struct CodexQuotaWidgetVerification {
    static func main() throws {
        try testBuildsSnapshotFromLatestTokenCountEvent()
        try testPrefersOverallCodexLimitOverLaterModelLimit()
        try testFallsBackToNextRolloutPathWhenFirstHasNoTokenCount()
        try testReturnsUnavailableWhenNoValidTokenCountExists()
        try testFormatsRefreshText()
        try testQueriesLatestRolloutPathsFromStateDatabase()
        print("All verification checks passed")
    }

    private static func testBuildsSnapshotFromLatestTokenCountEvent() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rollout = tempDir.appendingPathComponent("rollout.jsonl")
        try writeLines(
            [
                #"{"timestamp":"2026-06-13T17:37:16.849Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1781390198},"secondary":{"used_percent":15.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"plus"}}}"#,
                #"{"timestamp":"2026-06-13T17:37:54.911Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1781390198},"secondary":{"used_percent":15.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"plus"}}}"#
            ],
            to: rollout
        )

        let snapshot = try CodexQuotaSnapshotBuilder.build(
            fromRolloutPaths: [rollout],
            now: Date(timeIntervalSince1970: 1_781_379_000)
        )

        expect(snapshot.state == .ok, "Expected ok snapshot state")
        expect(snapshot.fiveHourRemainingPercent == 95, "Expected five-hour remaining percent")
        expect(snapshot.weekRemainingPercent == 85, "Expected week remaining percent")
        expect(snapshot.planType == "plus", "Expected plus plan type")
        expect(
            snapshot.sourceRolloutPath == rollout.path,
            "Expected source rollout path"
        )
        expect(
            snapshot.fiveHourResetAt == Date(timeIntervalSince1970: 1_781_390_198),
            "Expected five-hour reset date"
        )
        expect(
            snapshot.weekResetAt == Date(timeIntervalSince1970: 1_781_752_999),
            "Expected week reset date"
        )
    }

    private static func testPrefersOverallCodexLimitOverLaterModelLimit() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rollout = tempDir.appendingPathComponent("rollout.jsonl")
        try writeLines(
            [
                #"{"timestamp":"2026-06-14T23:31:53.088Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":3.0,"window_minutes":300,"resets_at":1781497727},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"prolite"}}}"#,
                #"{"timestamp":"2026-06-14T23:37:57.844Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1781498263},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1782085063},"plan_type":"prolite"}}}"#
            ],
            to: rollout
        )

        let snapshot = try CodexQuotaSnapshotBuilder.build(
            fromRolloutPaths: [rollout],
            now: Date(timeIntervalSince1970: 1_781_490_000)
        )

        expect(snapshot.state == .ok, "Expected ok state for overall codex limit")
        expect(snapshot.fiveHourRemainingPercent == 97, "Expected five-hour value from codex limit")
        expect(snapshot.weekRemainingPercent == 88, "Expected week value from codex limit")
        expect(
            snapshot.fiveHourResetAt == Date(timeIntervalSince1970: 1_781_497_727),
            "Expected five-hour reset from codex limit"
        )
        expect(
            snapshot.weekResetAt == Date(timeIntervalSince1970: 1_781_752_999),
            "Expected week reset from codex limit"
        )
    }

    private static func testFallsBackToNextRolloutPathWhenFirstHasNoTokenCount() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidRollout = tempDir.appendingPathComponent("invalid.jsonl")
        let validRollout = tempDir.appendingPathComponent("valid.jsonl")

        try writeLines(
            [
                #"{"timestamp":"2026-06-13T17:37:54.911Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#
            ],
            to: invalidRollout
        )

        try writeLines(
            [
                #"{"timestamp":"2026-06-13T17:37:54.911Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1781390198},"secondary":{"used_percent":25.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"plus"}}}"#
            ],
            to: validRollout
        )

        let snapshot = try CodexQuotaSnapshotBuilder.build(
            fromRolloutPaths: [invalidRollout, validRollout],
            now: Date(timeIntervalSince1970: 1_781_379_000)
        )

        expect(snapshot.state == .ok, "Expected ok state after fallback")
        expect(snapshot.fiveHourRemainingPercent == 88, "Expected five-hour fallback value")
        expect(snapshot.weekRemainingPercent == 75, "Expected week fallback value")
        expect(
            snapshot.sourceRolloutPath == validRollout.path,
            "Expected fallback rollout path"
        )
    }

    private static func testReturnsUnavailableWhenNoValidTokenCountExists() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rollout = tempDir.appendingPathComponent("rollout.jsonl")
        try writeLines(
            [
                #"{"timestamp":"2026-06-13T17:37:54.911Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#
            ],
            to: rollout
        )

        let snapshot = try CodexQuotaSnapshotBuilder.build(
            fromRolloutPaths: [rollout],
            now: Date(timeIntervalSince1970: 1_781_379_000)
        )

        expect(snapshot.state == .unavailable, "Expected unavailable state")
        expect(snapshot.fiveHourRemainingPercent == nil, "Expected nil five-hour value")
        expect(snapshot.weekRemainingPercent == nil, "Expected nil week value")
        expect(snapshot.sourceRolloutPath == nil, "Expected nil source rollout path")
    }

    private static func testFormatsRefreshText() throws {
        let fiveHourRing = QuotaRingSnapshot(
            label: "5小时",
            remainingPercent: 95,
            resetAt: Date(timeIntervalSince1970: 1_781_390_198)
        )
        let weekRing = QuotaRingSnapshot(
            label: "1周",
            remainingPercent: 85,
            resetAt: Date(timeIntervalSince1970: 1_781_752_999)
        )

        let fiveHourText = QuotaRefreshFormatter.displayText(
            for: fiveHourRing,
            style: .fiveHour,
            now: Date(timeIntervalSince1970: 1_781_379_000),
            locale: Locale(identifier: "zh_Hans_CN"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        let weekDateText = QuotaRefreshFormatter.displayText(
            for: weekRing,
            style: .week,
            now: Date(timeIntervalSince1970: 1_781_650_000),
            locale: Locale(identifier: "zh_Hans_CN"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        let weekTimeText = QuotaRefreshFormatter.displayText(
            for: weekRing,
            style: .week,
            now: Date(timeIntervalSince1970: 1_781_740_000),
            locale: Locale(identifier: "zh_Hans_CN"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )

        expect(fiveHourText == "06:36", "Expected five-hour time text")
        expect(weekDateText == "6月18日", "Expected week date text")
        expect(weekTimeText == "11:23", "Expected week time text")
    }

    private static func testQueriesLatestRolloutPathsFromStateDatabase() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.sqlite")
        let db = try SQLiteDatabase(path: dbURL.path)
        defer { try? db.close() }

        try db.execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        try db.execute(
            """
            INSERT INTO threads (id, rollout_path, updated_at_ms, archived) VALUES
            ('old', '/tmp/old.jsonl', 1000, 0),
            ('archived', '/tmp/archived.jsonl', 3000, 1),
            ('new', '/tmp/new.jsonl', 2000, 0);
            """
        )

        let paths = try SQLiteThreadPathProvider(databasePath: dbURL)
            .recentRolloutPaths(limit: 5)

        expect(paths == [
            URL(fileURLWithPath: "/tmp/new.jsonl"),
            URL(fileURLWithPath: "/tmp/old.jsonl"),
        ], "Expected rollout paths ordered by updated_at_ms")
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Verification failed: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeLines(_ lines: [String], to url: URL) throws {
    let data = lines.joined(separator: "\n").data(using: .utf8)!
    try data.write(to: url)
}
