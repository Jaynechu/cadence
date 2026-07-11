import ArgumentParser
import Foundation

enum DBPath {
    static let calendar = "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
    static let notes = "~/Library/Group Containers/group.com.apple.Notes/NoteStore.sqlite"

    // Reminders store UUID varies per machine; a Mac can hold several stores
    // (local + one per iCloud account). Pick the most recently written one
    // (max mtime of .sqlite and its -wal), or honor CADENCE_REM_STORE.
    static var reminders: String {
        if let override = ProcessInfo.processInfo.environment["CADENCE_REM_STORE"],
           !override.isEmpty {
            return NSString(string: override).expandingTildeInPath
        }
        let storesDir = NSString(string: "~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores").expandingTildeInPath
        let fm = FileManager.default
        func lastWrite(_ path: String) -> Date {
            let dates = [path, path + "-wal"].compactMap {
                (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
            }
            return dates.max() ?? .distantPast
        }
        if let files = try? fm.contentsOfDirectory(atPath: storesDir) {
            let candidates = files.filter { $0.hasSuffix(".sqlite") }
                .map { "\(storesDir)/\($0)" }
            if let best = candidates.max(by: { lastWrite($0) < lastWrite($1) }) {
                return best
            }
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
