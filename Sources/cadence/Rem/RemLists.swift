import ArgumentParser
import Foundation

struct RemLists: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lists",
        abstract: "List all Reminder lists with open reminder counts."
    )

    @Flag(name: .long, help: "Human-readable output.") var human: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.reminders)

        let sql = """
        SELECT l.ZNAME as name, COUNT(r.Z_PK) as count
        FROM ZREMCDBASELIST l
        LEFT JOIN ZREMCDREMINDER r
            ON r.ZLIST = l.Z_PK AND r.ZMARKEDFORDELETION = 0 AND r.ZCOMPLETED = 0
        WHERE l.ZMARKEDFORDELETION = 0
          AND l.ZNAME IS NOT NULL
          AND l.ZNAME != ''
          AND l.ZNAME NOT IN ('Reminders', 'SiriFoundInApps')
        GROUP BY l.Z_PK, l.ZNAME
        ORDER BY l.ZNAME
        """

        let rows = try db.query(sql)

        if human {
            for row in rows {
                let name = row["name"] as? String ?? ""
                let count = row["count"] as? Int64 ?? 0
                print("\(name) (\(count))")
            }
        } else {
            let dicts: [[String: Any]] = rows.map { row in
                [
                    "name": row["name"] as? String ?? "",
                    "count": row["count"] as? Int64 ?? 0
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
    }
}
