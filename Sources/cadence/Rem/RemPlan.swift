import ArgumentParser
import Darwin
import EventKit
import Foundation

struct RemPlan: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Pre-create one placeholder reminder per day for the coming week."
    )

    @Option(name: .long, help: "Title of each placeholder reminder.") var prefix: String
    @Option(name: .long, help: "List name (default: Inbox).") var list: String = "Inbox"
    @Option(name: .long, help: "Number of consecutive days to cover (default: 7).") var days: Int = 7
    @Option(name: .long, help: "First day YYYY-MM-DD (default: Monday of next week).") var start: String?
    @Flag(name: .long, help: "Print what would be created without creating it.") var dryRun: Bool = false
    @Flag(name: .long, help: "Human-readable output.") var human: Bool = false

    func run() throws {
        guard days > 0 else {
            fputs("--days must be greater than 0\n", stderr)
            throw ExitCode(1)
        }
        let startDate: Date
        if let s = start {
            guard let d = DateUtil.parseDate(s) else {
                fputs("Invalid --start '\(s)'. Use YYYY-MM-DD.\n", stderr)
                throw ExitCode(1)
            }
            startDate = d
        } else {
            startDate = RemPlan.nextWeekMonday(from: Date())
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DateUtil.melbourneTZ
        let dates = (0..<days).map { cal.date(byAdding: .day, value: $0, to: startDate)! }
        let dayKeys = dates.map { RemPlan.dayKey($0) }

        let taken = try existingDays()
        let pending = zip(dates, dayKeys).filter { !taken.contains($0.1) }
        let skipped = dayKeys.filter { taken.contains($0) }

        if dryRun {
            report(start: dayKeys[0], created: pending.map { $0.1 }, skipped: skipped)
            return
        }
        if pending.isEmpty {
            report(start: dayKeys[0], created: [], skipped: skipped)
            return
        }

        let store = EKEventStore()
        store.requestFullAccessToReminders { granted, error in
            guard granted else {
                let detail = error.map { ": \($0.localizedDescription)" } ?? ""
                fputs("Reminders access denied\(detail)\n", stderr)
                Darwin.exit(1)
            }
            guard let target = store.calendars(for: .reminder).first(where: { $0.title == self.list }) else {
                fputs("List '\(self.list)' not found.\n", stderr)
                Darwin.exit(1)
            }

            var created: [String] = []
            for (date, key) in pending {
                let reminder = EKReminder(eventStore: store)
                reminder.title = self.prefix
                reminder.calendar = target
                reminder.dueDateComponents = DateUtil.dateOnlyComponentsInMelbourne(date)
                do {
                    try store.save(reminder, commit: true)
                } catch {
                    fputs("Failed to save reminder for \(key): \(error)\n", stderr)
                    Darwin.exit(1)
                }
                RemWriter.setAllDay(uid: reminder.calendarItemIdentifier, isDateOnly: true)
                created.append(key)
            }
            self.report(start: dayKeys[0], created: created, skipped: skipped)
            Darwin.exit(0)
        }
        dispatchMain()
    }

    func existingDays() throws -> Set<String> {
        let db = try SQLiteDB(path: DBPath.reminders)
        let rows = try db.query("""
        SELECT ZTITLE as title, ZDUEDATE as due_date
        FROM ZREMCDREMINDER
        WHERE ZMARKEDFORDELETION = 0 AND ZCOMPLETED = 0 AND ZDUEDATE IS NOT NULL
        """)
        var days = Set<String>()
        for row in rows {
            guard let title = row["title"] as? String, title.hasPrefix(prefix) else { continue }
            let ts: Double?
            if let d = row["due_date"] as? Double { ts = d }
            else if let i = row["due_date"] as? Int64 { ts = Double(i) }
            else { ts = nil }
            guard let stamp = ts else { continue }
            days.insert(String(DateUtil.formatISOFromLocalCoreData(stamp).prefix(10)))
        }
        return days
    }

    func report(start: String, created: [String], skipped: [String]) {
        if human {
            print("start: \(start)")
            for d in created { print("  + \(d)  \(prefix)") }
            for d in skipped { print("  = \(d)  already planned") }
            if created.isEmpty && skipped.isEmpty { print("  (nothing to do)") }
            return
        }
        let out: [String: Any] = ["start": start, "created": created, "skipped": skipped]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = DateUtil.melbourneTZ
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func nextWeekMonday(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DateUtil.melbourneTZ
        let today = DateUtil.startOfDay(date)
        let weekday = cal.component(.weekday, from: today)
        let sinceMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: 7 - sinceMonday, to: today)!
    }
}
