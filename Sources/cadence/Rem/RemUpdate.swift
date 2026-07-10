import ArgumentParser
import EventKit
import Foundation
import Darwin

struct RemUpdate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a reminder's fields."
    )

    @Argument(help: "Reminder Z_PK id (from rem read).") var id: Int
    @Option(name: .long, help: "New due date (YYYY-MM-DD or YYYY-MM-DD HH:MM). Pass 'none' to clear.") var due: String?
    @Option(name: .long, help: "New start date (YYYY-MM-DD or YYYY-MM-DD HH:MM). Pass 'none' to clear.") var start: String?
    @Option(name: .long, help: "New title.") var title: String?
    @Option(name: .long, help: "New notes. Pass 'none' to clear.") var notes: String?
    @Option(name: .long, help: "Priority: 0=none, 1=high, 5=medium, 9=low.") var priority: Int?
    @Option(name: .long, help: "Move to a different list by name.") var list: String?
    @Option(name: .long, help: "New location. Pass 'none' to clear.") var location: String?

    func run() throws {
        let db = try SQLiteDB(path: DBPath.reminders)
        let rows = try db.query("SELECT ZTITLE as title, ZDACALENDARITEMUNIQUEIDENTIFIER as uid FROM ZREMCDREMINDER WHERE Z_PK = \(id)")
        guard let row = rows.first, let origTitle = row["title"] as? String, let uid = row["uid"] as? String else {
            throw ValidationError("Reminder id \(id) not found.")
        }

        var dueIsDateOnly: Bool? = nil
        if let dueStr = due, dueStr.lowercased() != "none" {
            dueIsDateOnly = DateUtil.isDateOnly(dueStr)
        }

        let store = EKEventStore()
        store.requestFullAccessToReminders { granted, error in
            guard granted else {
                fputs("Reminders access denied\n", stderr)
                Darwin.exit(1)
            }

            guard let item = store.calendarItem(withIdentifier: uid) as? EKReminder else {
                fputs("Could not find reminder '\(origTitle)' (uid=\(uid)) in EventKit\n", stderr)
                Darwin.exit(1)
            }

            var changed: [String] = []

            if let newTitle = self.title {
                item.title = newTitle
                changed.append("title")
            }

            if let dueStr = self.due {
                if dueStr.lowercased() == "none" {
                    item.dueDateComponents = nil
                    changed.append("due=cleared")
                } else if let comps = DateUtil.smartComponents(dueStr) {
                    item.dueDateComponents = comps
                    changed.append("due=\(dueStr)")
                } else {
                    fputs("Invalid due date '\(dueStr)'. Use YYYY-MM-DD or YYYY-MM-DD HH:MM.\n", stderr)
                    Darwin.exit(1)
                }
            }

            if let startStr = self.start {
                if startStr.lowercased() == "none" {
                    item.startDateComponents = nil
                    changed.append("start=cleared")
                } else if let comps = DateUtil.smartComponents(startStr) {
                    item.startDateComponents = comps
                    changed.append("start=\(startStr)")
                } else {
                    fputs("Invalid start date '\(startStr)'. Use YYYY-MM-DD or YYYY-MM-DD HH:MM.\n", stderr)
                    Darwin.exit(1)
                }
            }

            if let newNotes = self.notes {
                item.notes = newNotes.lowercased() == "none" ? nil : newNotes
                changed.append("notes")
            }

            if let newPriority = self.priority {
                item.priority = newPriority
                changed.append("priority=\(newPriority)")
            }

            if let listName = self.list {
                let lists = store.calendars(for: .reminder)
                if let cal = lists.first(where: { $0.title == listName }) {
                    item.calendar = cal
                    changed.append("list=\(listName)")
                } else {
                    fputs("List '\(listName)' not found.\n", stderr)
                    Darwin.exit(1)
                }
            }

            if let locStr = self.location {
                if let existingAlarms = item.alarms {
                    for alarm in existingAlarms where alarm.structuredLocation != nil {
                        item.removeAlarm(alarm)
                    }
                }
                if locStr.lowercased() == "none" {
                    changed.append("location=cleared")
                } else {
                    let structuredLocation = EKStructuredLocation(title: locStr)
                    let alarm = EKAlarm()
                    alarm.structuredLocation = structuredLocation
                    alarm.proximity = .enter
                    item.addAlarm(alarm)
                    changed.append("location=\(locStr)")
                }
            }

            if changed.isEmpty {
                fputs("Nothing to update. Pass at least one of --due, --start, --title, --notes, --priority, --list, --location.\n", stderr)
                Darwin.exit(1)
            }

            do {
                try store.save(item, commit: true)

                if let isDateOnly = dueIsDateOnly {
                    let allDay = isDateOnly ? 1 : 0
                    try? SQLiteDB.executeRW(
                        path: DBPath.reminders,
                        sql: "UPDATE ZREMCDREMINDER SET ZALLDAY = ?, ZDISPLAYDATEISALLDAY = ? WHERE Z_PK = ?",
                        bindings: [allDay, allDay, self.id])
                }

                let out: [String: Any] = ["id": self.id, "title": item.title ?? origTitle, "updated": changed]
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
