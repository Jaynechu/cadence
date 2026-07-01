import ArgumentParser
import Foundation

struct RemRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read reminders."
    )

    @Flag(name: .long, help: "Due today or overdue, not completed (default).") var today: Bool = false
    @Flag(name: .long, help: "Due before today, not completed.") var overdue: Bool = false
    @Flag(name: .long, help: "Due in next 7 days, not completed.") var week: Bool = false
    @Flag(name: .long, help: "All not-completed reminders.") var all: Bool = false
    @Option(name: .long, help: "Filter by list name (case-insensitive contains).") var list: String?
    @Flag(name: .long, help: "Show completed reminders.") var done: Bool = false
    @Flag(name: .long, help: "Output as JSON (default).") var json: Bool = false
    @Flag(name: .long, help: "Human-readable output.") var human: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.reminders)

        var whereClause = "WHERE r.ZMARKEDFORDELETION = 0"

        let now = Date()
        // ZDUEDATE stores local wall-clock time as if it were UTC, so bounds must be
        // converted with toLocalCoreData (not toCoreData) to match that convention.
        let todayStart = DateUtil.toLocalCoreData(DateUtil.startOfDay(now))
        let todayEnd = DateUtil.toLocalCoreData(DateUtil.endOfDay(now))
        let weekEnd = DateUtil.toLocalCoreData(DateUtil.endOfDay(now.addingTimeInterval(7 * 86400)))

        if done {
            whereClause += " AND r.ZCOMPLETED = 1"
        } else if overdue {
            whereClause += " AND r.ZCOMPLETED = 0 AND r.ZDUEDATE IS NOT NULL AND r.ZDUEDATE < \(todayStart)"
        } else if week {
            whereClause += " AND r.ZCOMPLETED = 0 AND r.ZDUEDATE IS NOT NULL AND r.ZDUEDATE < \(weekEnd)"
        } else if all {
            whereClause += " AND r.ZCOMPLETED = 0"
        } else {
            // default: today (due today only, not completed)
            whereClause += " AND r.ZCOMPLETED = 0 AND r.ZDUEDATE IS NOT NULL AND r.ZDUEDATE >= \(todayStart) AND r.ZDUEDATE < \(todayEnd)"
        }

        if let listFilter = list {
            // SQLite LIKE — escape single quotes
            let escaped = listFilter.replacingOccurrences(of: "'", with: "''")
            whereClause += " AND LOWER(l.ZNAME) LIKE '%\(escaped.lowercased())%'"
        }

        let sql = """
        SELECT r.Z_PK as id, r.ZTITLE as title, r.ZNOTES as notes,
               r.ZPRIORITY as priority, r.ZFLAGGED as flagged, r.ZCOMPLETED as completed,
               r.ZDUEDATE as due_date, r.ZSTARTDATE as start_date,
               r.ZCOMPLETIONDATE as completion_date,
               r.ZCREATIONDATE as creation_date, r.ZALLDAY as all_day,
               r.ZICSURL as url,
               l.ZNAME as list_name,
               r.ZPARENTREMINDER as parent_id
        FROM ZREMCDREMINDER r
        LEFT JOIN ZREMCDBASELIST l ON r.ZLIST = l.Z_PK
        \(whereClause)
        ORDER BY CASE WHEN r.ZDUEDATE IS NULL THEN 1 ELSE 0 END ASC,
                 r.ZDUEDATE ASC,
                 r.ZPRIORITY ASC
        """

        let rows = try db.query(sql)

        if human && !json {
            printHuman(rows)
        } else {
            printJSON(rows)
        }
    }

    func tsValue(_ val: Any?) -> Double? {
        if let d = val as? Double { return d }
        if let i = val as? Int64 { return Double(i) }
        return nil
    }

    func rowToDict(_ row: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        if let id = row["id"] as? Int64 { out["id"] = id }
        if let t = row["title"] as? String { out["title"] = t }
        if let n = row["notes"] as? String, !n.isEmpty { out["notes"] = n }
        if let p = row["priority"] as? Int64 { out["priority"] = p }
        if let f = row["flagged"] as? Int64 { out["flagged"] = f != 0 }
        if let c = row["completed"] as? Int64 { out["completed"] = c != 0 }
        if let ts = tsValue(row["due_date"]) {
            out["due_date"] = DateUtil.formatISOFromLocalCoreData(ts)
        }
        if let ts = tsValue(row["start_date"]) {
            out["start_date"] = DateUtil.formatISOFromLocalCoreData(ts)
        }
        if let ts = tsValue(row["completion_date"]) {
            out["completion_date"] = DateUtil.formatISO(DateUtil.fromCoreData(ts))
        }
        if let l = row["list_name"] as? String { out["list"] = l }
        if let u = row["url"] as? String, !u.isEmpty { out["url"] = u }
        if let pid = row["parent_id"] as? Int64 { out["parent_id"] = pid }
        return out
    }

    func printJSON(_ rows: [[String: Any?]]) {
        let dicts = rows.map { rowToDict($0) }
        if let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    func printHuman(_ rows: [[String: Any?]]) {
        // Group by list
        var groupMap: [String: [[String: Any?]]] = [:]
        var groupOrder: [String] = []

        for row in rows {
            let key = row["list_name"] as? String ?? "No List"
            if groupMap[key] == nil {
                groupMap[key] = []
                groupOrder.append(key)
            }
            groupMap[key]!.append(row)
        }

        for listName in groupOrder {
            let items = groupMap[listName]!
            print("\n[\(listName)]")
            for item in items {
                let title = item["title"] as? String ?? "(no title)"
                let id = item["id"] as? Int64 ?? 0
                let flagged = (item["flagged"] as? Int64) != 0
                let priority = item["priority"] as? Int64 ?? 0
                var prefix = ""
                if flagged { prefix += "🚩" }
                if priority == 1 { prefix += "❗" }
                else if priority == 5 { prefix += "⚡" }

                var dueStr = ""
                if let ts = tsValue(item["due_date"]) {
                    dueStr = "  due:\(DateUtil.formatISOFromLocalCoreData(ts))"
                }

                print("  \(prefix)[\(id)] \(title)\(dueStr)")
                if let notes = item["notes"] as? String, !notes.isEmpty {
                    print("      \(notes)")
                }
            }
        }
        if rows.isEmpty { print("No reminders found.") }
    }
}
