import ArgumentParser
import EventKit
import Foundation
import Darwin

struct CalDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a calendar event by UUID."
    )

    @Option(name: .long, help: "Event UUID (from cal read).") var id: String
    @Flag(name: .long, help: "Skip confirmation.") var force: Bool = false

    func run() throws {
        if !force {
            fputs("Refusing to delete without --force. Pass --force to confirm deletion of event '\(id)'.\n", stderr)
            throw ExitCode.failure
        }

        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, error in
            guard granted else {
                fputs("Calendar access denied\n", stderr)
                Darwin.exit(1)
            }

            // Search by external identifier
            let calendars = store.calendars(for: .event)
            var foundEvent: EKEvent?

            // Try calendarItem(withIdentifier:) first
            if let item = store.calendarItem(withIdentifier: self.id) as? EKEvent {
                foundEvent = item
            }

            // Fallback: search last year range
            if foundEvent == nil {
                let start = Date().addingTimeInterval(-365 * 86400)
                let end = Date().addingTimeInterval(365 * 86400)
                let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
                let events = store.events(matching: pred)
                foundEvent = events.first { $0.calendarItemExternalIdentifier == self.id }
            }

            guard let event = foundEvent else {
                fputs("Event not found: \(self.id)\n", stderr)
                Darwin.exit(1)
            }

            do {
                try store.remove(event, span: .thisEvent)
                print("{\"deleted\":\"\(self.id)\"}")
                Darwin.exit(0)
            } catch {
                fputs("Failed to delete: \(error)\n", stderr)
                Darwin.exit(1)
            }
        }
        dispatchMain()
    }
}
