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
    @Option(name: .long, help: "List name (default: Inbox).") var list: String = "Inbox"
    @Option(name: .long, help: "Due datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var due: String?
    @Option(name: .long, help: "Start datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var start: String?
    @Option(name: .long, help: "Priority: 0=none, 1=high, 5=medium, 9=low.") var priority: Int = 0
    @Option(name: .long, help: "Notes.") var notes: String?
    @Option(name: .long, help: "URL.") var url: String?
    @Flag(name: .long, help: "Flag this reminder.") var flag: Bool = false
    @Option(name: .long, help: "Repeat spec FREQ;INTERVAL e.g. monthly;1, yearly;1.") var `repeat`: String?
    @Option(name: .long, help: "Location name/address — adds a location-based alarm.") var location: String?

    func run() throws {
        let dueComps = due.flatMap { DateUtil.smartComponents($0) }
        let startComps = start.flatMap { DateUtil.smartComponents($0) }
        let dueIsDateOnly = due.map { DateUtil.isDateOnly($0) }

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

            if let d = dueComps {
                reminder.dueDateComponents = d
            }
            if let s = startComps {
                reminder.startDateComponents = s
            }

            if let repeatSpec = self.`repeat` {
                let parts = repeatSpec.split(separator: ";", maxSplits: 1)
                if parts.count == 2, let interval = Int(parts[1]), interval > 0 {
                    let freqMap: [String: EKRecurrenceFrequency] = [
                        "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly
                    ]
                    if let freq = freqMap[String(parts[0]).lowercased()] {
                        let rule = EKRecurrenceRule(recurrenceWith: freq, interval: interval, end: nil)
                        reminder.recurrenceRules = [rule]
                    } else {
                        fputs("Unknown repeat frequency '\(parts[0])'. Use daily/weekly/monthly/yearly.\n", stderr)
                    }
                } else {
                    fputs("Invalid repeat spec '\(repeatSpec)'. Use FREQ;INTERVAL e.g. monthly;1\n", stderr)
                }
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

                if let isDateOnly = dueIsDateOnly {
                    let uid = reminder.calendarItemIdentifier
                    let allDay = isDateOnly ? 1 : 0
                    try? SQLiteDB.executeRW(
                        path: DBPath.reminders,
                        sql: "UPDATE ZREMCDREMINDER SET ZALLDAY = ?, ZDISPLAYDATEISALLDAY = ? WHERE ZDACALENDARITEMUNIQUEIDENTIFIER = ?",
                        bindings: [allDay, allDay, uid])
                }

                if let locationString = self.location {
                    let structuredLocation = EKStructuredLocation(title: locationString)
                    let alarm = EKAlarm()
                    alarm.structuredLocation = structuredLocation
                    alarm.proximity = .enter
                    reminder.addAlarm(alarm)
                    try store.save(reminder, commit: true)
                }

                // If flag requested, use AppleScript after save
                if self.flag {
                    let safeTitle = ScriptRunner.escapeForAppleScript(self.title)
                    let script = "tell application \"Reminders\" to set flagged of (first reminder whose name is \"\(safeTitle)\") to true"
                    _ = try? ScriptRunner.osascript(script)
                }

                var out: [String: Any] = [
                    "title": reminder.title ?? "",
                    "list": reminder.calendar?.title ?? "",
                    "priority": reminder.priority,
                    "flagged": self.flag
                ]
                if let locationString = self.location { out["location"] = locationString }
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
