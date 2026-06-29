import ArgumentParser
import Foundation

enum DBPath {
    static let calendar = "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
    static let notes = "~/Library/Group Containers/group.com.apple.Notes/NoteStore.sqlite"

    // Reminders store UUID varies per machine; discover first .sqlite in Stores dir
    static var reminders: String {
        let storesDir = NSString(string: "~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores").expandingTildeInPath
        if let files = try? FileManager.default.contentsOfDirectory(atPath: storesDir),
           let sqliteFile = files.first(where: { $0.hasSuffix(".sqlite") }) {
            return "\(storesDir)/\(sqliteFile)"
        }
        return "~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-8A2E9A6D-FC6A-4654-8BB0-2ED02C0143B6.sqlite"
    }
}

@main
struct AppleData: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cadence",
        abstract: "Read and write Apple Calendar and Reminders data.",
        subcommands: [Cal.self, Rem.self, Note.self]
    )
}
