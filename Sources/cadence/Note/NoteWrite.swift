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

        let metaRows = try db.query("SELECT Z_UUID FROM Z_METADATA LIMIT 1")
        guard let storeUUID = metaRows.first?["Z_UUID"] as? String else {
            fputs("Could not read Notes store UUID.\n", stderr)
            throw ExitCode.failure
        }
        let asId = "x-coredata://\(storeUUID)/ICNote/p\(id)"
        let escapedBody = ScriptRunner.escapeForAppleScript(body)

        let script: String

        if append {
            script = """
            tell application "Notes"
                set n to first note whose id is "\(asId)"
                set currentBody to body of n
                set body of n to currentBody & "<br>\(escapedBody)"
                return "ok"
            end tell
            """
        } else {
            let escapedTitle = ScriptRunner.escapeForAppleScript(title)
            let htmlBody = "<html><body><h1>\(escapedTitle)</h1><p>\(escapedBody)</p></body></html>"
            let escapedHTML = ScriptRunner.escapeForAppleScript(htmlBody)
            script = """
            tell application "Notes"
                set n to first note whose id is "\(asId)"
                set body of n to "\(escapedHTML)"
                return "ok"
            end tell
            """
        }

        do {
            try ScriptRunner.osascript(script)
        } catch {
            fputs("AppleScript error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        let action = append ? "Appended to" : "Updated"
        print("\(action): \"\(title)\" [id=\(id)]")
    }
}
