import ArgumentParser
import EventKit
import Foundation
import Darwin

struct RemDone: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a reminder as completed (or undone)."
    )

    @Argument(help: "Reminder Z_PK id (from rem read).") var id: Int
    @Flag(name: .long, help: "Mark as not completed instead.") var undone: Bool = false

    func run() throws {
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

            item.isCompleted = !self.undone
            do {
                try store.save(item, commit: true)
                let status = self.undone ? "undone" : "done"
                let out: [String: Any] = ["id": self.id, "title": title, "status": status]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) { print(str) }
                Darwin.exit(0)
            } catch {
                fputs("Failed to save: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
        dispatchMain()
    }
}
