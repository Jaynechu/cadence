import ArgumentParser
import Darwin
import EventKit
import Foundation

struct RemPlan: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Pre-create one placeholder reminder per day for the coming week."
    )

    @Option(name: .long, help: "Title of each placeholder reminder (with --countdown, prefix of 'D<n>'-style titles).") var prefix: String
    @Option(name: .long, help: "List name (default: Inbox).") var list: String = "Inbox"
    @Option(name: .long, help: "Number of consecutive days to cover (default: 7).") var days: Int = 7
    @Option(name: .long, help: "First day YYYY-MM-DD (default: Monday of next week).") var start: String?
    @Option(name: .long, help: "Target day YYYY-MM-DD. Title becomes prefix + days left until it; days after it are skipped.") var countdown: String?
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
        var targetDate: Date?
        if let c = countdown {
            guard let d = DateUtil.parseDate(c) else {
                fputs("Invalid --countdown '\(c)'. Use YYYY-MM-DD.\n", stderr)
                throw ExitCode(1)
            }
            targetDate = d
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DateUtil.melbourneTZ
        let startKey = RemPlan.dayKey(startDate)
        var plan: [(date: Date, key: String, title: String)] = []
        for offset in 0..<days {
            let date = cal.date(byAdding: .day, value: offset, to: startDate)!
            var title = prefix
            if let target = targetDate {
                let left = cal.dateComponents([.day], from: date, to: target).day!
                if left < 0 { break }
                title = prefix + String(left)
            }
            plan.append((date, RemPlan.dayKey(date), title))
        }

        let existing = try existingTitles()
        let isTaken: ((date: Date, key: String, title: String)) -> Bool = {
            existing[$0.key]?.contains($0.title) ?? false
        }
        let pending = plan.filter { !isTaken($0) }
        let skipped = plan.filter(isTaken).map { $0.key }

        if dryRun {
            report(start: startKey, created: pending.map { ($0.key, $0.title) }, skipped: skipped)
            return
        }
        if pending.isEmpty {
            report(start: startKey, created: [], skipped: skipped)
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

            var created: [(String, String)] = []
            for (date, key, title) in pending {
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.calendar = target
                reminder.dueDateComponents = DateUtil.dateOnlyComponentsInMelbourne(date)
                do {
                    try store.save(reminder, commit: true)
                } catch {
                    fputs("Failed to save reminder for \(key): \(error)\n", stderr)
                    Darwin.exit(1)
                }
                RemWriter.setAllDay(uid: reminder.calendarItemIdentifier, isDateOnly: true)
                created.append((key, title))
            }
            self.report(start: startKey, created: created, skipped: skipped)
            Darwin.exit(0)
        }
        dispatchMain()
    }

    func existingTitles() throws -> [String: Set<String>] {
        let db = try SQLiteDB(path: DBPath.reminders)
        let rows = try db.query("""
        SELECT ZTITLE as title, ZDUEDATE as due_date
        FROM ZREMCDREMINDER
        WHERE ZMARKEDFORDELETION = 0 AND ZCOMPLETED = 0 AND ZDUEDATE IS NOT NULL
        """)
        var days: [String: Set<String>] = [:]
        for row in rows {
            guard let title = row["title"] as? String, title.hasPrefix(prefix) else { continue }
            let ts: Double?
            if let d = row["due_date"] as? Double { ts = d }
            else if let i = row["due_date"] as? Int64 { ts = Double(i) }
            else { ts = nil }
            guard let stamp = ts else { continue }
            days[String(DateUtil.formatISOFromLocalCoreData(stamp).prefix(10)), default: []].insert(title)
        }
        return days
    }

    func report(start: String, created: [(day: String, title: String)], skipped: [String]) {
        if human {
            print("start: \(start)")
            for c in created { print("  + \(c.day)  \(c.title)") }
            for d in skipped { print("  = \(d)  already planned") }
            if created.isEmpty && skipped.isEmpty { print("  (nothing to do)") }
            return
        }
        let out: [String: Any] = ["start": start, "created": created.map { $0.day }, "skipped": skipped]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    static func dayKey(_ date: Date) -> String {
        DateUtil.dayFormatter.string(from: date)
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
