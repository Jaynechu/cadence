import ArgumentParser
import Foundation

struct NoteList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List notes."
    )

    @Option(name: .long, help: "Filter by folder name (case-insensitive contains).") var folder: String?
    @Flag(name: .long, help: "Output as JSON.") var json: Bool = false
    @Flag(name: .long, help: "Human-readable output (default).") var human: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.notes)

        var whereClause = "WHERE n.Z_ENT = 12 AND n.ZTITLE1 IS NOT NULL AND n.ZMARKEDFORDELETION = 0 AND (f.ZFOLDERTYPE IS NULL OR f.ZFOLDERTYPE != 1)"

        if let folderFilter = folder {
            let escaped = folderFilter.replacingOccurrences(of: "'", with: "''")
            whereClause += " AND LOWER(f.ZTITLE2) LIKE '%\(escaped.lowercased())%'"
        }

        let sql = """
        SELECT n.Z_PK as id,
               n.ZTITLE1 as title,
               n.ZSNIPPET as snippet,
               n.ZHASCHECKLIST as has_checklist,
               n.ZISPINNED as is_pinned,
               n.ZIDENTIFIER as identifier,
               n.ZCREATIONDATE3 as created,
               n.ZMODIFICATIONDATE1 as modified,
               f.ZTITLE2 as folder_name
        FROM ZICCLOUDSYNCINGOBJECT n
        LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
        \(whereClause)
        ORDER BY f.ZTITLE2 ASC, n.ZMODIFICATIONDATE1 DESC
        """

        let rows = try db.query(sql)

        if json && !human {
            printJSON(rows)
        } else {
            printHuman(rows)
        }
    }

    func rowToDict(_ row: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        if let id = row["id"] as? Int64 { out["id"] = id }
        if let v = row["identifier"] as? String { out["identifier"] = v }
        if let v = row["title"] as? String { out["title"] = v }
        if let v = row["snippet"] as? String { out["snippet"] = v }
        if let v = row["folder_name"] as? String { out["folder"] = v }
        if let v = row["is_pinned"] as? Int64 { out["pinned"] = v != 0 }
        if let v = row["has_checklist"] as? Int64 { out["has_checklist"] = v != 0 }
        if let v = row["created"] as? Double {
            out["created"] = DateUtil.formatISO(DateUtil.fromCoreData(v))
        }
        if let v = row["modified"] as? Double {
            out["modified"] = DateUtil.formatISO(DateUtil.fromCoreData(v))
        }
        if let id = row["identifier"] as? String {
            out["url"] = "notes://showNote?identifier=\(id)"
        }
        return out
    }

    func printJSON(_ rows: [[String: Any?]]) {
        let dicts = rows.map { rowToDict($0) }
        if let data = try? JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys, .prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    func printHuman(_ rows: [[String: Any?]]) {
        var groupMap: [String: [[String: Any?]]] = [:]
        var groupOrder: [String] = []

        for row in rows {
            let key = row["folder_name"] as? String ?? "No Folder"
            if groupMap[key] == nil {
                groupMap[key] = []
                groupOrder.append(key)
            }
            groupMap[key]!.append(row)
        }

        for folderName in groupOrder {
            let items = groupMap[folderName]!
            print("\n[\(folderName)]")
            for item in items {
                let title = item["title"] as? String ?? "(no title)"
                let id = item["id"] as? Int64 ?? 0
                let pinned = (item["is_pinned"] as? Int64) != 0
                let checklist = (item["has_checklist"] as? Int64) != 0

                var flags = ""
                if pinned { flags += "📌" }
                if checklist { flags += "☑️ " }

                var snippetStr = ""
                if let s = item["snippet"] as? String, !s.isEmpty {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    let preview = String(trimmed.prefix(50))
                    snippetStr = preview.count < trimmed.count ? "  — \(preview)…" : "  — \(preview)"
                }

                print("  \(flags)[\(id)] \(title)\(snippetStr)")
            }
        }

        if rows.isEmpty { print("No notes found.") }
    }
}
