import ArgumentParser
import Foundation

struct NoteDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a note by its ID (Z_PK from note list)."
    )

    @Argument(help: "Note ID (Z_PK from note list).") var id: Int
    @Flag(name: .long, help: "Skip confirmation.") var force: Bool = false

    func run() throws {
        if !force {
            fputs("Refusing to delete without --force. Pass --force to confirm deletion of note id \(id).\n", stderr)
            throw ExitCode.failure
        }

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

        let script = """
        tell application "Notes"
            delete note id "\(asId)"
        end tell
        """

        do {
            try ScriptRunner.osascript(script)
        } catch {
            fputs("AppleScript error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        let out: [String: Any] = ["deleted": id, "title": title]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
