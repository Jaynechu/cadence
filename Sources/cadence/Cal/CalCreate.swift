import ArgumentParser
import EventKit
import Foundation
import Darwin

struct CalCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a calendar event."
    )

    @Option(name: .long, help: "Event title.") var title: String
    @Option(name: .long, help: "Start datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var start: String
    @Option(name: .long, help: "End datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var end: String
    @Option(name: .long, help: "Calendar name (default: Study).") var calendar: String = "Study"
    @Option(name: .long, help: "Notes/description.") var notes: String?
    @Option(name: .long, help: "URL.") var url: String?
    @Option(name: .long, help: "Location.") var location: String?
    @Flag(name: .long, help: "All-day event.") var allDay: Bool = false

    func run() throws {
        guard let startDate = DateUtil.parseInput(start) else {
            throw ValidationError("Invalid start datetime: \(start)")
        }
        guard let endDate = DateUtil.parseInput(end) else {
            throw ValidationError("Invalid end datetime: \(end)")
        }

        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, error in
            guard granted else {
                fputs("Calendar access denied\n", stderr)
                Darwin.exit(1)
            }

            let event = EKEvent(eventStore: store)
            event.title = self.title
            event.startDate = startDate
            event.endDate = endDate
            event.isAllDay = self.allDay
            if let n = self.notes { event.notes = n }
            if let u = self.url, let urlObj = URL(string: u) { event.url = urlObj }
            if let l = self.location { event.location = l }

            // Find calendar
            let cals = store.calendars(for: .event)
            if let cal = cals.first(where: { $0.title == self.calendar }) {
                event.calendar = cal
            } else if let def = store.defaultCalendarForNewEvents {
                event.calendar = def
                fputs("Calendar '\(self.calendar)' not found, using default: \(def.title)\n", stderr)
            } else {
                fputs("Calendar '\(self.calendar)' not found and no default calendar available.\n", stderr)
                Darwin.exit(1)
            }

            do {
                try store.save(event, span: .thisEvent)
                let out: [String: Any] = [
                    "id": event.calendarItemIdentifier,
                    "title": event.title ?? "",
                    "start": DateUtil.formatISO(event.startDate),
                    "end": DateUtil.formatISO(event.endDate),
                    "calendar": event.calendar?.title ?? ""
                ]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
                Darwin.exit(0)
            } catch {
                fputs("Failed to save event: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
        dispatchMain()
    }
}
