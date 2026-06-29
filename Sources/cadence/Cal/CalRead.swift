import ArgumentParser
import Foundation

struct CalRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read calendar events."
    )

    @Argument(help: "Dates to read (YYYY-MM-DD). Defaults to yesterday, today, tomorrow.")
    var dates: [String] = []

    @Flag(name: .long, help: "Output as JSON (default).")
    var json: Bool = false

    @Flag(name: .long, help: "Output in human-readable format.")
    var human: Bool = false

    static let skipCalendars: Set<String> = ["Birthdays", "Facebook Birthdays"]

    func run() throws {
        let targetDates: [Date]
        if dates.isEmpty {
            let today = Date()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            targetDates = [yesterday, today, tomorrow]
        } else {
            targetDates = try dates.map { str in
                guard let d = DateUtil.parseDate(str) else {
                    throw ValidationError("Invalid date: \(str). Use YYYY-MM-DD.")
                }
                return d
            }
        }

        let db = try SQLiteDB(path: DBPath.calendar)

        var allEvents: [[String: Any?]] = []

        for date in targetDates {
            let start = DateUtil.toCoreData(DateUtil.startOfDay(date))
            let end = DateUtil.toCoreData(DateUtil.endOfDay(date))

            let sql = """
            SELECT ci.summary as summary,
                   ci.start_date as start_date,
                   ci.end_date as end_date,
                   ci.all_day as all_day,
                   c.title as calendar_name,
                   ci.description as description,
                   loc.title as location,
                   ci.url as url,
                   ci.UUID as uuid
            FROM CalendarItem ci
            JOIN Calendar c ON ci.calendar_id = c.ROWID
            LEFT JOIN Location loc ON loc.item_owner_id = ci.ROWID
            WHERE ci.start_date < \(end) AND (ci.end_date IS NULL OR ci.end_date > \(start))
              AND ci.hidden = 0
              AND c.title NOT IN ('Birthdays', 'Facebook Birthdays')
            ORDER BY ci.start_date ASC
            """

            let rows = try db.query(sql)
            allEvents.append(contentsOf: rows)
        }

        // Deduplicate by uuid
        var seen = Set<String>()
        let deduped = allEvents.filter { row in
            let uuid = row["uuid"] as? String ?? UUID().uuidString
            return seen.insert(uuid).inserted
        }

        // Sort by start_date
        let sorted = deduped.sorted { a, b in
            let aStart = (a["start_date"] as? Double) ?? 0
            let bStart = (b["start_date"] as? Double) ?? 0
            return aStart < bStart
        }

        if human && !json {
            printHuman(sorted)
        } else {
            printJSON(sorted)
        }
    }

    func eventToDict(_ row: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        if let s = row["summary"] as? String { out["title"] = s }
        if let ts = row["start_date"] as? Double {
            out["start"] = DateUtil.formatISO(DateUtil.fromCoreData(ts))
        }
        if let ts = row["end_date"] as? Double {
            out["end"] = DateUtil.formatISO(DateUtil.fromCoreData(ts))
        }
        if let ad = row["all_day"] as? Int64 { out["all_day"] = ad != 0 }
        if let cal = row["calendar_name"] as? String { out["calendar"] = cal }
        if let notes = row["description"] as? String { out["description"] = notes }
        if let loc = row["location"] as? String { out["location"] = loc }
        if let url = row["url"] as? String { out["url"] = url }
        if let uuid = row["uuid"] as? String { out["uuid"] = uuid }
        return out
    }

    func printJSON(_ rows: [[String: Any?]]) {
        let dicts = rows.map { eventToDict($0) }
        if let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys]) {
            print(String(data: data, encoding: .utf8) ?? "[]")
        }
    }

    func printHuman(_ rows: [[String: Any?]]) {
        // Group by date
        var groups: [(String, [[String: Any?]])] = []
        var groupMap: [String: [[String: Any?]]] = [:]
        var groupOrder: [String] = []

        for row in rows {
            let ts = row["start_date"] as? Double ?? 0
            let date = DateUtil.fromCoreData(ts)
            let key = DateUtil.formatDate(date)
            if groupMap[key] == nil {
                groupMap[key] = []
                groupOrder.append(key)
            }
            groupMap[key]!.append(row)
        }
        groups = groupOrder.map { ($0, groupMap[$0]!) }

        for (dateStr, events) in groups {
            print("\n\(dateStr)")
            print(String(repeating: "-", count: dateStr.count))
            for event in events {
                let title = event["summary"] as? String ?? "(no title)"
                let cal = event["calendar_name"] as? String ?? ""
                let isAllDay = (event["all_day"] as? Int64) != 0
                if isAllDay {
                    print("  [all-day] \(title)  [\(cal)]")
                } else {
                    var timeStr = ""
                    if let ts = event["start_date"] as? Double {
                        timeStr = DateUtil.formatHuman(DateUtil.fromCoreData(ts))
                    }
                    if let ts = event["end_date"] as? Double {
                        timeStr += "-" + DateUtil.formatHuman(DateUtil.fromCoreData(ts))
                    }
                    print("  \(timeStr)  \(title)  [\(cal)]")
                }
                if let loc = event["location"] as? String, !loc.isEmpty {
                    print("    @ \(loc)")
                }
            }
        }
        if rows.isEmpty { print("No events found.") }
    }
}
