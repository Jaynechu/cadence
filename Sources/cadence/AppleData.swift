import ArgumentParser
import Foundation

enum DBPath {
    static let calendar = "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
    static let notes = "~/Library/Group Containers/group.com.apple.Notes/NoteStore.sqlite"

    // Reminders store UUID varies per machine; discover the live .sqlite in Stores dir.
    // A machine can have multiple stores (e.g. stale husks from old iCloud syncs). File
    // modification dates are unreliable here — background sync daemons (and even read-only
    // queries, via WAL auto-checkpoint) touch .sqlite/.sqlite-wal/.sqlite-shm on empty husks
    // too, so mtime can't distinguish them. Pick the store that actually contains reminder rows.
    static var reminders: String {
        let storesDir = NSString(string: "~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores").expandingTildeInPath
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: storesDir) {
            let sqliteFiles = files.filter { !$0.hasPrefix(".") && $0.hasSuffix(".sqlite") }
            func reminderCount(_ sqliteFile: String) -> Int64 {
                let path = "\(storesDir)/\(sqliteFile)"
                guard let db = try? SQLiteDB(path: path),
                      let rows = try? db.query("SELECT COUNT(*) AS c FROM ZREMCDREMINDER"),
                      let count = rows.first?["c"] as? Int64 else {
                    return -1
                }
                return count
            }
            if let sqliteFile = sqliteFiles.max(by: { reminderCount($0) < reminderCount($1) }) {
                return "\(storesDir)/\(sqliteFile)"
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
