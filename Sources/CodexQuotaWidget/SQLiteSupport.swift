import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case openDatabase(String)
    case prepareStatement(String)
    case execute(String)
    case step(String)

    public var description: String {
        switch self {
        case .openDatabase(let message),
             .prepareStatement(let message),
             .execute(let message),
             .step(let message):
            return message
        }
    }
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown open error"
            sqlite3_close(handle)
            throw SQLiteError.openDatabase(message)
        }
        self.handle = handle
    }

    public func close() throws {
        guard let handle else {
            return
        }

        if sqlite3_close(handle) != SQLITE_OK {
            throw SQLiteError.execute(lastErrorMessage(from: handle))
        }
        self.handle = nil
    }

    public func execute(_ sql: String) throws {
        guard let handle else {
            throw SQLiteError.execute("Database is closed")
        }

        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteError.execute(lastErrorMessage(from: handle))
        }
    }

    public func queryStrings(_ sql: String) throws -> [String] {
        guard let handle else {
            throw SQLiteError.step("Database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareStatement(lastErrorMessage(from: handle))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    rows.append(String(cString: text))
                }
                continue
            }
            if result == SQLITE_DONE {
                break
            }
            throw SQLiteError.step(lastErrorMessage(from: handle))
        }

        return rows
    }

    public func queryRows(_ sql: String) throws -> [[String?]] {
        guard let handle else {
            throw SQLiteError.step("Database is closed")
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareStatement(lastErrorMessage(from: handle))
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var rows: [[String?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                var row: [String?] = []
                for index in 0..<columnCount {
                    if let text = sqlite3_column_text(statement, index) {
                        row.append(String(cString: text))
                    } else {
                        row.append(nil)
                    }
                }
                rows.append(row)
                continue
            }
            if result == SQLITE_DONE {
                break
            }
            throw SQLiteError.step(lastErrorMessage(from: handle))
        }

        return rows
    }

    private func lastErrorMessage(from handle: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(handle))
    }
}

public struct SQLiteThreadPathProvider {
    public let databasePath: URL

    public init(databasePath: URL) {
        self.databasePath = databasePath
    }

    public func recentRolloutPaths(limit: Int) throws -> [URL] {
        let database = try SQLiteDatabase(path: databasePath.path)
        defer { try? database.close() }

        let sql = """
        SELECT rollout_path
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at_ms DESC
        LIMIT \(max(1, limit));
        """

        return try database.queryStrings(sql).map { URL(fileURLWithPath: $0) }
    }
}

public struct SQLiteCodexLogProvider {
    public let databasePath: URL

    public init(databasePath: URL) {
        self.databasePath = databasePath
    }

    public func recentRateLimitLogRows(limit: Int) throws -> [CodexLogRow] {
        let database = try SQLiteDatabase(path: databasePath.path)
        defer { try? database.close() }

        let sql = """
        SELECT ts, ts_nanos, target, feedback_log_body
        FROM logs
        WHERE feedback_log_body IS NOT NULL
          AND (
            (target = 'codex_api::endpoint::responses_websocket'
              AND feedback_log_body LIKE '%websocket event:%"type":"codex.rate_limits"%')
            OR
            (target = 'codex_client::default_client'
              AND feedback_log_body LIKE '%headers={%'
              AND feedback_log_body LIKE '%x-codex-primary-used-percent%')
          )
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT \(max(1, limit));
        """

        return try database.queryRows(sql).compactMap { row in
            guard row.count == 4,
                  let ts = row[0].flatMap(Int.init),
                  let tsNanos = row[1].flatMap(Int.init),
                  let target = row[2],
                  let body = row[3]
            else {
                return nil
            }

            return CodexLogRow(
                timestampSeconds: ts,
                timestampNanoseconds: tsNanos,
                target: target,
                body: body
            )
        }
    }
}

public struct CodexLogRow {
    public let timestampSeconds: Int
    public let timestampNanoseconds: Int
    public let target: String
    public let body: String

    public init(
        timestampSeconds: Int,
        timestampNanoseconds: Int,
        target: String,
        body: String
    ) {
        self.timestampSeconds = timestampSeconds
        self.timestampNanoseconds = timestampNanoseconds
        self.target = target
        self.body = body
    }
}
