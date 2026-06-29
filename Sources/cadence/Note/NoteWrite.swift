import ArgumentParser
import Foundation

struct NoteWrite: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "write",
        abstract: "Overwrite or append to a note body by its ID (Z_PK from note list)."
    )

    @Argument(help: "Note ID (Z_PK from note list).") var id: Int
    @Option(name: .long, help: "New body text to write.") var body: String
    @Flag(name: .long, help: "Append body to existing content instead of replacing.") var append: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.notes)

        let rows = try db.query(
            """
            SELECT n.ZTITLE1 as title
            FROM ZICCLOUDSYNCINGOBJECT n
            WHERE n.Z_ENT = 12 AND n.Z_PK = \(id)
            LIMIT 1
            """
        )

        guard let row = rows.first, let title = row["title"] as? String else {
            fputs("Note ID \(id) not found.\n", stderr)
            throw ExitCode.failure
        }

        // Fail early if multiple notes share this title
        let dups = try db.query(
            """
            SELECT n.Z_PK as id, f.ZTITLE2 as folder_name
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.Z_ENT = 12 AND n.ZTITLE1 = ? AND n.ZMARKEDFORDELETION = 0
            """,
            bindings: [title]
        )
        if dups.count > 1 {
            fputs("Ambiguous: \(dups.count) notes share title \"\(title)\":\n", stderr)
            for dup in dups {
                let did = dup["id"] as? Int64 ?? 0
                let df = dup["folder_name"] as? String ?? "?"
                fputs("  id=\(did) folder=\"\(df)\"\n", stderr)
            }
            throw ExitCode.failure
        }

        let escapedTitle = ScriptRunner.escapeForAppleScript(title)
        let escapedBody = ScriptRunner.escapeForAppleScript(body)

        let script: String

        if append {
            // Read existing body first, then append
            script = """
            tell application "Notes"
                set noteList to every note whose name is "\(escapedTitle)"
                if (count of noteList) > 0 then
                    set n to item 1 of noteList
                    set currentBody to body of n
                    set body of n to currentBody & "<br>\(escapedBody)"
                    return "ok"
                else
                    return "not_found"
                end if
            end tell
            """
        } else {
            let htmlBody = "<html><body><h1>\(escapedTitle)</h1><p>\(escapedBody)</p></body></html>"
            let escapedHTML = ScriptRunner.escapeForAppleScript(htmlBody)
            script = """
            tell application "Notes"
                set noteList to every note whose name is "\(escapedTitle)"
                if (count of noteList) > 0 then
                    set body of item 1 of noteList to "\(escapedHTML)"
                    return "ok"
                else
                    return "not_found"
                end if
            end tell
            """
        }

        let result: String
        do {
            result = try ScriptRunner.osascript(script)
        } catch {
            fputs("AppleScript error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "not_found" {
            fputs("Note \"\(title)\" not found in Notes app.\n", stderr)
            throw ExitCode.failure
        }

        let action = append ? "Appended to" : "Updated"
        print("\(action): \"\(title)\" [id=\(id)]")
    }
}
