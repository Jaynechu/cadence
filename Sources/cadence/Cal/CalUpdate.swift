import ArgumentParser
import EventKit
import Foundation
import Darwin

struct CalUpdate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a calendar event's fields by ID."
    )

    @Argument(help: "Event calendarItemIdentifier (from cal read).") var id: String
    @Option(name: .long, help: "New title.") var title: String?
    @Option(name: .long, help: "New start datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var start: String?
    @Option(name: .long, help: "New end datetime (YYYY-MM-DD HH:MM or YYYY-MM-DD).") var end: String?
    @Option(name: .long, help: "Move to different calendar by name.") var calendar: String?
    @Option(name: .long, help: "New notes. Pass 'none' to clear.") var notes: String?
    @Option(name: .long, help: "New location. Pass 'none' to clear.") var location: String?
    @Option(name: .long, help: "New URL. Pass 'none' to clear.") var url: String?

    func run() throws {
        if title == nil && start == nil && end == nil && calendar == nil
            && notes == nil && location == nil && url == nil {
            fputs("Nothing to update. Pass at least one of --title, --start, --end, --calendar, --notes, --location, --url.\n", stderr)
            throw ExitCode.failure
        }

        var startDate: Date?
        if let s = start {
            guard let d = DateUtil.parseInput(s) else {
                throw ValidationError("Invalid start datetime: \(s)")
            }
            startDate = d
        }

        var endDate: Date?
        if let e = end {
            guard let d = DateUtil.parseInput(e) else {
                throw ValidationError("Invalid end datetime: \(e)")
            }
            endDate = d
        }

        var newURL: URL?
        if let u = url, u.lowercased() != "none" {
            guard let parsed = URL(string: u) else {
                throw ValidationError("Invalid URL: \(u)")
            }
            newURL = parsed
        }

        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, error in
            guard granted else {
                fputs("Calendar access denied\n", stderr)
                Darwin.exit(1)
            }

            var foundEvent: EKEvent?

            // Try calendarItem(withIdentifier:) first
            if let item = store.calendarItem(withIdentifier: self.id) as? EKEvent {
                foundEvent = item
            }

            // Fallback: search by external identifier over a wide date range
            if foundEvent == nil {
                let calendars = store.calendars(for: .event)
                let searchStart = Date().addingTimeInterval(-365 * 86400)
                let searchEnd = Date().addingTimeInterval(365 * 86400)
                let pred = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: calendars)
                let events = store.events(matching: pred)
                foundEvent = events.first { $0.calendarItemExternalIdentifier == self.id }
            }

            guard let event = foundEvent else {
                fputs("Event not found: \(self.id)\n", stderr)
                Darwin.exit(1)
            }

            var changed: [String] = []

            if let newTitle = self.title {
                event.title = newTitle
                changed.append("title")
            }

            if let d = startDate {
                event.startDate = d
                changed.append("start")
            }

            if let d = endDate {
                event.endDate = d
                changed.append("end")
            }

            if let calName = self.calendar {
                let cals = store.calendars(for: .event)
                guard let cal = cals.first(where: { $0.title == calName }) else {
                    fputs("Calendar '\(calName)' not found.\n", stderr)
                    Darwin.exit(1)
                }
                event.calendar = cal
                changed.append("calendar")
            }

            if let newNotes = self.notes {
                event.notes = newNotes.lowercased() == "none" ? nil : newNotes
                changed.append("notes")
            }

            if let newLocation = self.location {
                event.location = newLocation.lowercased() == "none" ? nil : newLocation
                changed.append("location")
            }

            if self.url != nil {
                event.url = newURL
                changed.append("url")
            }

            do {
                try store.save(event, span: .thisEvent)
                let out: [String: Any] = [
                    "id": self.id,
                    "title": event.title ?? "",
                    "start": DateUtil.formatISO(event.startDate),
                    "end": DateUtil.formatISO(event.endDate),
                    "calendar": event.calendar?.title ?? "",
                    "updated": changed
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
