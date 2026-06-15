import Foundation
import CodexQuotaWidget

@main
struct CodexQuotaWidgetVerification {
    static func main() throws {
        try testBuildsSnapshotFromLatestTokenCountEvent()
        try testPrefersOverallCodexLimitOverLaterModelLimit()
        try testSelectsNewestOverallLimitAcrossRecentRollouts()
        try testBuildFromLocalStatePrefersFreshCodexLogs()
        try testBuildFromLocalStateChoosesNewerRolloutOverStaleLogs()
        try testIgnoresAssistantTextLogMatches()
        try testReadsLatestOverallLogQuotaOnly()
        try testNewerSourceEventPreventsFallbackOverwrite()
        try testSelectsNewestSnapshotStore()
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

    private static func testSelectsNewestOverallLimitAcrossRecentRollouts() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let staleRollout = tempDir.appendingPathComponent("stale-newer-thread.jsonl")
        let freshRollout = tempDir.appendingPathComponent("fresh-older-thread.jsonl")

        try writeLines(
            [
                #"{"timestamp":"2026-06-15T07:30:27.776Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":8.0,"window_minutes":300,"resets_at":1781497727},"secondary":{"used_percent":13.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"prolite"}}}"#,
                #"{"timestamp":"2026-06-15T07:46:06.468Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1781527535},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1782133535},"plan_type":"prolite"}}}"#
            ],
            to: staleRollout
        )
        try writeLines(
            [
                #"{"timestamp":"2026-06-15T07:34:28.814Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1781517688},"secondary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"prolite"}}}"#
            ],
            to: freshRollout
        )

        let snapshot = try CodexQuotaSnapshotBuilder.build(
            fromRolloutPaths: [staleRollout, freshRollout],
            now: Date(timeIntervalSince1970: 1_781_520_000)
        )

        expect(snapshot.state == .ok, "Expected ok state from newest overall codex event")
        expect(snapshot.fiveHourRemainingPercent == 85, "Expected five-hour value from newer codex event")
        expect(snapshot.weekRemainingPercent == 84, "Expected week value from newer codex event")
        expect(snapshot.sourceRolloutPath == freshRollout.path, "Expected source path from newer codex event")
    }

    private static func testBuildFromLocalStatePrefersFreshCodexLogs() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rollout = tempDir.appendingPathComponent("rollout.jsonl")
        try writeLines(
            [
                #"{"timestamp":"2026-06-15T07:34:28.814Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1781517688},"secondary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"prolite"}}}"#
            ],
            to: rollout
        )

        let stateDBURL = tempDir.appendingPathComponent("state.sqlite")
        let stateDB = try SQLiteDatabase(path: stateDBURL.path)
        defer { try? stateDB.close() }
        try stateDB.execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        try stateDB.execute(
            """
            INSERT INTO threads (id, rollout_path, updated_at_ms, archived) VALUES
            ('thread', '\(sqlStringLiteral(rollout.path))', 1000, 0);
            """
        )

        let logsDBURL = tempDir.appendingPathComponent("logs.sqlite")
        let logsDB = try makeLogsDatabase(at: logsDBURL)
        defer { try? logsDB.close() }

        let body = #"Request completed headers={"x-codex-plan-type":"prolite","x-codex-primary-used-percent":"20","x-codex-secondary-used-percent":"17","x-codex-primary-window-minutes":"300","x-codex-secondary-window-minutes":"10080","x-codex-primary-reset-at":"1781517688","x-codex-secondary-reset-at":"1781753000"} version=HTTP/1.1"#
        try insertLog(
            id: 101,
            ts: 1_781_510_327,
            tsNanos: 1,
            target: "codex_client::default_client",
            body: body,
            into: logsDB
        )

        let snapshot = try CodexQuotaSnapshotBuilder.buildFromLocalCodexState(
            stateDatabaseURL: stateDBURL,
            logsDatabaseURL: logsDBURL,
            now: Date(timeIntervalSince1970: 1_781_510_500)
        )

        expect(snapshot.state == .ok, "Expected ok state from logs")
        expect(snapshot.fiveHourRemainingPercent == 80, "Expected five-hour value from fresh logs")
        expect(snapshot.weekRemainingPercent == 83, "Expected week value from fresh logs")
        expect(snapshot.sourceRolloutPath == logsDBURL.path, "Expected logs database as source path")
        expect(snapshot.sourceEventAt == Date(timeIntervalSince1970: 1_781_510_327.000000001), "Expected source event time from logs")
    }

    private static func testIgnoresAssistantTextLogMatches() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logsDBURL = tempDir.appendingPathComponent("logs.sqlite")
        let logsDB = try makeLogsDatabase(at: logsDBURL)
        defer { try? logsDB.close() }

        let assistantText = #"websocket event: {"type":"response.output_text.done","text":"Use codex.rate_limits from the log"}"#
        try insertLog(
            id: 202,
            ts: 1_781_514_000,
            tsNanos: 1,
            target: "codex_api::endpoint::responses_websocket",
            body: assistantText,
            into: logsDB
        )

        let realRateLimit = #"websocket event: {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"primary":{"used_percent":36,"window_minutes":300,"reset_at":1781517688},"secondary":{"used_percent":19,"window_minutes":10080,"reset_at":1781752999}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":0,"window_minutes":300,"reset_at":1781531937},"secondary":{"used_percent":0,"window_minutes":10080,"reset_at":1782118737}}}}"#
        try insertLog(
            id: 201,
            ts: 1_781_513_900,
            tsNanos: 1,
            target: "codex_api::endpoint::responses_websocket",
            body: realRateLimit,
            into: logsDB
        )

        let snapshot = try CodexQuotaSnapshotBuilder.buildFromCodexLogs(
            logDatabaseURL: logsDBURL,
            now: Date(timeIntervalSince1970: 1_781_514_100)
        )

        expect(snapshot?.fiveHourRemainingPercent == 64, "Expected real websocket rate limit")
        expect(snapshot?.weekRemainingPercent == 81, "Expected real websocket week rate limit")
        expect(snapshot?.sourceEventAt == Date(timeIntervalSince1970: 1_781_513_900.000000001), "Expected fake assistant text to be ignored")
    }

    private static func testBuildFromLocalStateChoosesNewerRolloutOverStaleLogs() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rollout = tempDir.appendingPathComponent("rollout.jsonl")
        try writeLines(
            [
                #"{"timestamp":"2026-06-15T09:09:56.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1781517688},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1781752999},"plan_type":"prolite"}}}"#
            ],
            to: rollout
        )

        let stateDBURL = tempDir.appendingPathComponent("state.sqlite")
        let stateDB = try SQLiteDatabase(path: stateDBURL.path)
        defer { try? stateDB.close() }
        try stateDB.execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                rollout_path TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        try stateDB.execute(
            """
            INSERT INTO threads (id, rollout_path, updated_at_ms, archived) VALUES
            ('thread', '\(sqlStringLiteral(rollout.path))', 1000, 0);
            """
        )

        let logsDBURL = tempDir.appendingPathComponent("logs.sqlite")
        let logsDB = try makeLogsDatabase(at: logsDBURL)
        defer { try? logsDB.close() }

        let staleHeader = #"Request completed headers={"x-codex-plan-type":"prolite","x-codex-primary-used-percent":"28","x-codex-secondary-used-percent":"18","x-codex-primary-window-minutes":"300","x-codex-secondary-window-minutes":"10080","x-codex-primary-reset-at":"1781517688","x-codex-secondary-reset-at":"1781752999"} version=HTTP/1.1"#
        try insertLog(
            id: 251,
            ts: 1_781_511_700,
            tsNanos: 1,
            target: "codex_client::default_client",
            body: staleHeader,
            into: logsDB
        )

        let snapshot = try CodexQuotaSnapshotBuilder.buildFromLocalCodexState(
            stateDatabaseURL: stateDBURL,
            logsDatabaseURL: logsDBURL,
            now: Date(timeIntervalSince1970: 1_781_514_100)
        )

        expect(snapshot.fiveHourRemainingPercent == 60, "Expected newer rollout value over stale logs")
        expect(snapshot.weekRemainingPercent == 80, "Expected newer rollout week value over stale logs")
        expect(snapshot.sourceRolloutPath == rollout.path, "Expected newer rollout source path")
    }

    private static func testReadsLatestOverallLogQuotaOnly() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logsDBURL = tempDir.appendingPathComponent("logs.sqlite")
        let logsDB = try makeLogsDatabase(at: logsDBURL)
        defer { try? logsDB.close() }

        let header = #"Request completed headers={"x-codex-plan-type":"prolite","x-codex-primary-used-percent":"28","x-codex-secondary-used-percent":"18","x-codex-primary-window-minutes":"300","x-codex-secondary-window-minutes":"10080","x-codex-primary-reset-at":"1781517688","x-codex-secondary-reset-at":"1781752999","x-codex-bengalfox-primary-used-percent":"0","x-codex-bengalfox-secondary-used-percent":"0","x-codex-bengalfox-primary-reset-at":"1781529696","x-codex-bengalfox-secondary-reset-at":"1782116496"} version=HTTP/1.1"#
        try insertLog(
            id: 302,
            ts: 1_781_511_700,
            tsNanos: 1,
            target: "codex_client::default_client",
            body: header,
            into: logsDB
        )

        let olderWebSocket = #"websocket event: {"type":"codex.rate_limits","plan_type":"prolite","rate_limits":{"primary":{"used_percent":36,"window_minutes":300,"reset_at":1781517688},"secondary":{"used_percent":19,"window_minutes":10080,"reset_at":1781752999}},"additional_rate_limits":{"GPT-5.3-Codex-Spark":{"primary":{"used_percent":0,"window_minutes":300,"reset_at":1781531937},"secondary":{"used_percent":0,"window_minutes":10080,"reset_at":1782118737}}}}"#
        try insertLog(
            id: 301,
            ts: 1_781_511_600,
            tsNanos: 1,
            target: "codex_api::endpoint::responses_websocket",
            body: olderWebSocket,
            into: logsDB
        )

        let snapshot = try CodexQuotaSnapshotBuilder.buildFromCodexLogs(
            logDatabaseURL: logsDBURL,
            now: Date(timeIntervalSince1970: 1_781_511_800)
        )

        expect(snapshot?.fiveHourRemainingPercent == 72, "Expected top-level HTTP primary value")
        expect(snapshot?.weekRemainingPercent == 82, "Expected top-level HTTP secondary value")
        expect(snapshot?.sourceEventAt == Date(timeIntervalSince1970: 1_781_511_700.000000001), "Expected newest real total quota event")
    }

    private static func testNewerSourceEventPreventsFallbackOverwrite() throws {
        let current = CodexQuotaSnapshot(
            state: .ok,
            fiveHourRemainingPercent: 64,
            fiveHourResetAt: Date(timeIntervalSince1970: 1_781_517_688),
            weekRemainingPercent: 81,
            weekResetAt: Date(timeIntervalSince1970: 1_781_752_999),
            snapshotAt: Date(timeIntervalSince1970: 1_781_514_000),
            planType: "prolite",
            sourceRolloutPath: "/tmp/logs.sqlite",
            sourceEventAt: Date(timeIntervalSince1970: 1_781_513_900)
        )
        let staleFallback = CodexQuotaSnapshot(
            state: .ok,
            fiveHourRemainingPercent: 72,
            fiveHourResetAt: Date(timeIntervalSince1970: 1_781_517_688),
            weekRemainingPercent: 82,
            weekResetAt: Date(timeIntervalSince1970: 1_781_752_999),
            snapshotAt: Date(timeIntervalSince1970: 1_781_514_100),
            planType: "prolite",
            sourceRolloutPath: "/tmp/rollout.jsonl"
        )

        expect(!current.shouldBeReplaced(by: staleFallback), "Expected stale fallback to be rejected")
        expect(staleFallback.shouldBeReplaced(by: current), "Expected event-backed snapshot to replace fallback")
    }

    private static func testSelectsNewestSnapshotStore() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldStore = SharedSnapshotStore(fileURL: tempDir.appendingPathComponent("old.json"))
        let newStore = SharedSnapshotStore(fileURL: tempDir.appendingPathComponent("new.json"))

        try oldStore.save(
            CodexQuotaSnapshot(
                state: .ok,
                fiveHourRemainingPercent: 72,
                fiveHourResetAt: Date(timeIntervalSince1970: 1_781_517_688),
                weekRemainingPercent: 82,
                weekResetAt: Date(timeIntervalSince1970: 1_781_752_999),
                snapshotAt: Date(timeIntervalSince1970: 1_781_511_700),
                planType: "prolite",
                sourceRolloutPath: "/tmp/logs.sqlite",
                sourceEventAt: Date(timeIntervalSince1970: 1_781_511_700)
            )
        )
        try newStore.save(
            CodexQuotaSnapshot(
                state: .ok,
                fiveHourRemainingPercent: 64,
                fiveHourResetAt: Date(timeIntervalSince1970: 1_781_517_688),
                weekRemainingPercent: 81,
                weekResetAt: Date(timeIntervalSince1970: 1_781_752_999),
                snapshotAt: Date(timeIntervalSince1970: 1_781_513_900),
                planType: "prolite",
                sourceRolloutPath: "/tmp/logs.sqlite",
                sourceEventAt: Date(timeIntervalSince1970: 1_781_513_900)
            )
        )

        let snapshot = SharedSnapshotStore.newestOKSnapshot(from: [oldStore, newStore])
        expect(snapshot?.fiveHourRemainingPercent == 64, "Expected newest store snapshot")
        expect(snapshot?.sourceEventAt == Date(timeIntervalSince1970: 1_781_513_900), "Expected newest source event time")
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

private func makeLogsDatabase(at url: URL) throws -> SQLiteDatabase {
    let db = try SQLiteDatabase(path: url.path)
    try db.execute(
        """
        CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            ts_nanos INTEGER NOT NULL,
            level TEXT NOT NULL,
            target TEXT NOT NULL,
            feedback_log_body TEXT,
            module_path TEXT,
            file TEXT,
            line INTEGER,
            thread_id TEXT,
            process_uuid TEXT,
            estimated_bytes INTEGER NOT NULL DEFAULT 0
        );
        """
    )
    return db
}

private func insertLog(
    id: Int,
    ts: Int,
    tsNanos: Int,
    target: String,
    body: String,
    into db: SQLiteDatabase
) throws {
    try db.execute(
        """
        INSERT INTO logs (id, ts, ts_nanos, level, target, feedback_log_body) VALUES
        (\(id), \(ts), \(tsNanos), 'INFO', '\(sqlStringLiteral(target))', '\(sqlStringLiteral(body))');
        """
    )
}

private func sqlStringLiteral(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}
