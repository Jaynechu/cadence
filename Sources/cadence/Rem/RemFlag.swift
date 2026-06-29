import ArgumentParser
import Foundation

struct RemFlag: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flag",
        abstract: "Flag or unflag a reminder."
    )

    @Argument(help: "Reminder Z_PK id (from rem read).") var id: Int
    @Flag(name: .long, help: "Unflag instead.") var unflag: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.reminders)
        let rows = try db.query("SELECT ZTITLE as title, ZDACALENDARITEMUNIQUEIDENTIFIER as uid FROM ZREMCDREMINDER WHERE Z_PK = \(id)")
        guard let row = rows.first, let title = row["title"] as? String, let uid = row["uid"] as? String else {
            throw ValidationError("Reminder id \(id) not found.")
        }

        let flagValue = unflag ? "false" : "true"
        let asId = "x-apple-reminder://\(uid)"
        let script = "tell application \"Reminders\" to set flagged of (first reminder whose id is \"\(asId)\") to \(flagValue)"

        do {
            try ScriptRunner.osascript(script)
            let action = unflag ? "unflagged" : "flagged"
            let out: [String: Any] = ["id": id, "title": title, "status": action]
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } catch {
            fputs("AppleScript error: \(error)\n", stderr)
            throw ExitCode.failure
        }
    }
}
