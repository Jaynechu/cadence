import Foundation
import SQLite3

class SQLiteDB {
    private var db: OpaquePointer?

    init(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard sqlite3_open_v2(expandedPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "SQLiteDB", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        sqlite3_busy_timeout(db, 3000)
    }

    func query(_ sql: String, bindings: [Any?] = []) throws -> [[String: Any?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "SQLiteDB", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        defer { sqlite3_finalize(stmt) }

        for (idx, binding) in bindings.enumerated() {
            let pos = Int32(idx + 1)
            if let b = binding {
                if let i = b as? Int64 {
                    sqlite3_bind_int64(stmt, pos, i)
                } else if let i = b as? Int {
                    sqlite3_bind_int64(stmt, pos, Int64(i))
                } else if let d = b as? Double {
                    sqlite3_bind_double(stmt, pos, d)
                } else if let s = b as? String {
                    sqlite3_bind_text(stmt, pos, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                sqlite3_bind_null(stmt, pos)
            }
        }

        var results: [[String: Any?]] = []
        let colCount = sqlite3_column_count(stmt)

        var stepResult = sqlite3_step(stmt)
        while stepResult == SQLITE_ROW {
            var row: [String: Any?] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL: row[name] = nil
                default: row[name] = nil
                }
            }
            results.append(row)
            stepResult = sqlite3_step(stmt)
        }

        if stepResult != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "SQLiteDB", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "sqlite3_step failed (\(stepResult)): \(err)"])
        }

        return results
    }

    static func executeRW(path: String, sql: String, bindings: [Any?] = []) throws {
        var rwDb: OpaquePointer?
        let expanded = NSString(string: path).expandingTildeInPath
        guard sqlite3_open_v2(expanded, &rwDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(rwDb))
            throw NSError(domain: "SQLiteDB", code: 4, userInfo: [NSLocalizedDescriptionKey: err])
        }
        defer { sqlite3_close(rwDb) }
        sqlite3_busy_timeout(rwDb, 3000)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(rwDb, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(rwDb))
            throw NSError(domain: "SQLiteDB", code: 5, userInfo: [NSLocalizedDescriptionKey: err])
        }
        defer { sqlite3_finalize(stmt) }

        for (idx, binding) in bindings.enumerated() {
            let pos = Int32(idx + 1)
            if let b = binding {
                if let i = b as? Int64 {
                    sqlite3_bind_int64(stmt, pos, i)
                } else if let i = b as? Int {
                    sqlite3_bind_int64(stmt, pos, Int64(i))
                } else if let d = b as? Double {
                    sqlite3_bind_double(stmt, pos, d)
                } else if let s = b as? String {
                    sqlite3_bind_text(stmt, pos, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            } else {
                sqlite3_bind_null(stmt, pos)
            }
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let err = String(cString: sqlite3_errmsg(rwDb))
            throw NSError(domain: "SQLiteDB", code: 6, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    deinit { if db != nil { sqlite3_close(db) } }
}
