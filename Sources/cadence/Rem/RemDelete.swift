import ArgumentParser
import EventKit
import Foundation
import Darwin

struct RemDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a reminder by Z_PK id."
    )

    @Option(name: .long, help: "Reminder Z_PK id (from rem read).") var id: Int
    @Flag(name: .long, help: "Skip confirmation.") var force: Bool = false

    func run() throws {
        if !force {
            fputs("Refusing to delete without --force. Pass --force to confirm deletion of reminder id \(id).\n", stderr)
            throw ExitCode.failure
        }

        let db = try SQLiteDB(path: DBPath.reminders)
        let rows = try db.query("SELECT ZTITLE as title, ZDACALENDARITEMUNIQUEIDENTIFIER as uid FROM ZREMCDREMINDER WHERE Z_PK = \(id)")
        guard let row = rows.first, let title = row["title"] as? String, let uid = row["uid"] as? String else {
            throw ValidationError("Reminder id \(id) not found in SQLite.")
        }

        let store = EKEventStore()
        store.requestFullAccessToReminders { granted, error in
            guard granted else {
                fputs("Reminders access denied\n", stderr)
                Darwin.exit(1)
            }

            guard let item = store.calendarItem(withIdentifier: uid) as? EKReminder else {
                fputs("Could not find reminder '\(title)' (uid=\(uid)) in EventKit\n", stderr)
                Darwin.exit(1)
            }

            do {
                try store.remove(item, commit: true)
                print("{\"deleted\":\(self.id),\"title\":\"\(title)\"}")
                Darwin.exit(0)
            } catch {
                fputs("Failed to delete: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
        dispatchMain()
    }
}
