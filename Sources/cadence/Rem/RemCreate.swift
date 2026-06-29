import ArgumentParser
import EventKit
import Foundation
import Darwin

struct RemCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a reminder."
    )

    @Option(name: .long, help: "Title.") var title: String
    @Option(name: .long, help: "List name (default: Inbox 📫).") var list: String = "Inbox 📫"
    @Option(name: .long, help: "Due datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var due: String?
    @Option(name: .long, help: "Start datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var start: String?
    @Option(name: .long, help: "Priority: 0=none, 1=high, 5=medium, 9=low.") var priority: Int = 0
    @Option(name: .long, help: "Notes.") var notes: String?
    @Option(name: .long, help: "URL.") var url: String?
    @Flag(name: .long, help: "Flag this reminder.") var flag: Bool = false

    func run() throws {
        let dueDate = due.flatMap { DateUtil.parseInput($0) }
        let startDate = start.flatMap { DateUtil.parseInput($0) }

        let store = EKEventStore()
        store.requestFullAccessToReminders { granted, error in
            guard granted else {
                fputs("Reminders access denied\n", stderr)
                Darwin.exit(1)
            }

            let reminder = EKReminder(eventStore: store)
            reminder.title = self.title
            reminder.priority = self.priority
            if let n = self.notes { reminder.notes = n }
            if let u = self.url { reminder.url = URL(string: u) }

            if let d = dueDate {
                reminder.dueDateComponents = DateUtil.dateComponentsInMelbourne(d)
            }
            if let s = startDate {
                reminder.startDateComponents = DateUtil.dateComponentsInMelbourne(s)
            }

            // Find list
            let lists = store.calendars(for: .reminder)
            if let cal = lists.first(where: { $0.title == self.list }) {
                reminder.calendar = cal
            } else if let def = store.defaultCalendarForNewReminders() {
                reminder.calendar = def
                fputs("List '\(self.list)' not found, using default: \(def.title)\n", stderr)
            } else {
                fputs("List '\(self.list)' not found and no default list available.\n", stderr)
                Darwin.exit(1)
            }

            do {
                try store.save(reminder, commit: true)

                // If flag requested, use AppleScript after save
                if self.flag {
                    let safeTitle = ScriptRunner.escapeForAppleScript(self.title)
                    let script = "tell application \"Reminders\" to set flagged of (first reminder whose name is \"\(safeTitle)\") to true"
                    try? ScriptRunner.osascript(script)
                }

                let out: [String: Any] = [
                    "title": reminder.title ?? "",
                    "list": reminder.calendar?.title ?? "",
                    "priority": reminder.priority,
                    "flagged": self.flag
                ]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
                Darwin.exit(0)
            } catch {
                fputs("Failed to save reminder: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
        dispatchMain()
    }
}
