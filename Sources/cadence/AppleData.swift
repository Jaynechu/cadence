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
        FileHandle.standardError.write(Data("""
        cadence: could not locate the Reminders store under \(storesDir).
        Ensure Reminders is set up and the terminal/binary has Full Disk Access.
        \n
        """.utf8))
        exit(1)
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
