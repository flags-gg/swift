#if canImport(SQLite3)
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Flags kept on disk, so the last fetched values survive an app restart. Same schema as the Kotlin SDK.
public actor SQLiteCache: Cache {
    private let db: OpaquePointer

    public init(path: String = "flags_cache.db") throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw FlagError.cacheError("Failed to open SQLite cache at \(path)")
        }
        db = handle // from here deinit closes it, including if the schema below fails
        let schema = """
            CREATE TABLE IF NOT EXISTS flags (name TEXT PRIMARY KEY, enabled INTEGER NOT NULL, id TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS refresh_info (id INTEGER PRIMARY KEY, last_refresh REAL NOT NULL, interval_allowed INTEGER NOT NULL);
            INSERT OR IGNORE INTO refresh_info (id, last_refresh, interval_allowed) VALUES (1, 0, 60);
            """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            throw FlagError.cacheError("Failed to create SQLite cache: \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func get(_ name: String) async throws -> (enabled: Bool, exists: Bool) {
        let stmt = try prepare("SELECT enabled FROM flags WHERE name = ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (false, false) }
        return (sqlite3_column_int(stmt, 0) == 1, true)
    }

    public func getAll() async throws -> [FeatureFlag] {
        let stmt = try prepare("SELECT name, enabled, id FROM flags")
        defer { sqlite3_finalize(stmt) }
        var flags: [FeatureFlag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            flags.append(FeatureFlag(
                enabled: sqlite3_column_int(stmt, 1) == 1,
                details: Details(name: text(stmt, 0), id: text(stmt, 2))
            ))
        }
        return flags
    }

    public func refresh(_ flags: [FeatureFlag], intervalAllowed: Int) async throws {
        try exec("BEGIN")
        do {
            try exec("DELETE FROM flags")
            let insert = try prepare("INSERT OR REPLACE INTO flags (name, enabled, id) VALUES (?, ?, ?)")
            defer { sqlite3_finalize(insert) }
            for flag in flags {
                sqlite3_reset(insert)
                sqlite3_bind_text(insert, 1, flag.details.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(insert, 2, flag.enabled ? 1 : 0)
                sqlite3_bind_text(insert, 3, flag.details.id, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(insert) == SQLITE_DONE else { throw lastError() }
            }
            let update = try prepare("UPDATE refresh_info SET last_refresh = ?, interval_allowed = ? WHERE id = 1")
            defer { sqlite3_finalize(update) }
            sqlite3_bind_double(update, 1, Date().timeIntervalSince1970)
            sqlite3_bind_int(update, 2, Int32(clamping: intervalAllowed))
            guard sqlite3_step(update) == SQLITE_DONE else { throw lastError() }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func shouldRefreshCache() async -> Bool {
        guard let stmt = try? prepare("SELECT last_refresh, interval_allowed FROM refresh_info WHERE id = 1") else { return true }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return true }
        let next = sqlite3_column_double(stmt, 0) + Double(sqlite3_column_int(stmt, 1))
        return Date().timeIntervalSince1970 > next
    }

    /// Forces the next check to refresh; the stored flags stay as the fallback.
    public func initialize() async throws {
        try exec("UPDATE refresh_info SET last_refresh = 0 WHERE id = 1")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
        return stmt
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func text(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    private func lastError() -> FlagError {
        .cacheError(String(cString: sqlite3_errmsg(db)))
    }
}
#endif
