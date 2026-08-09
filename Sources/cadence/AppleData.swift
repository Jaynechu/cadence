import ArgumentParser
import Foundation

enum DBPath {
    static let calendar = "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
    static let notes = "~/Library/Group Containers/group.com.apple.Notes/NoteStore.sqlite"

    // Reminders store UUID varies per machine; a Mac can hold several stores
    // (local + one per iCloud account). Honor CADENCE_REM_STORE if set, otherwise
    // discover via two-phase selection: find the newest mtime, filter candidates within
    // 60 s of it (the freshness window), then pick the one with the highest row count.
    // A probe failure (-1) is treated as lowest count, not a disqualification — the
    // freshness window already handles locked live stores. Result is cached for the
    // process lifetime (CLI is short-lived; re-discovery would be incorrect).
    static let reminders: String = {
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

        func reminderCount(_ path: String) -> Int64 {
            guard let db = try? SQLiteDB(path: path),
                  let rows = try? db.query("SELECT COUNT(*) AS c FROM ZREMCDREMINDER"),
                  let count = rows.first?["c"] as? Int64 else {
                return -1
            }
            return count
        }

        guard let files = try? fm.contentsOfDirectory(atPath: storesDir) else {
            FileHandle.standardError.write(Data("""
            cadence: could not locate the Reminders store under \(storesDir).
            Ensure Reminders is set up and the terminal/binary has Full Disk Access.
            \n
            """.utf8))
            exit(1)
        }

        let candidates = files
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".sqlite") }
            .map { "\(storesDir)/\($0)" }

        guard !candidates.isEmpty else {
            FileHandle.standardError.write(Data("""
            cadence: could not locate the Reminders store under \(storesDir).
            Ensure Reminders is set up and the terminal/binary has Full Disk Access.
            \n
            """.utf8))
            exit(1)
        }

        // Build (path, mtime, count) once — no re-invocation per comparison.
        let scored = candidates.map { path -> (path: String, mtime: Date, count: Int64) in
            (path: path, mtime: lastWrite(path), count: reminderCount(path))
        }

        // Two-phase selection (deterministic regardless of candidate order):
        // 1. Find the newest mtime among all candidates.
        // 2. Keep candidates within 60 s of that newest mtime (the "freshness window").
        // 3. Among those, pick the one with the highest row count; treat -1 (probe
        //    failure) as lowest (Int64.min). If every candidate in the window is -1,
        //    the freshness-window filter already left us with the newest-mtime store,
        //    so falling back to first() is correct.
        let newestMtime = scored.map(\.mtime).max()!
        let window = scored.filter { newestMtime.timeIntervalSince($0.mtime) <= 60 }
        let best = window.max { a, b in
            let ac = a.count >= 0 ? a.count : Int64.min
            let bc = b.count >= 0 ? b.count : Int64.min
            return ac < bc
        }!

        return best.path
    }()
}

@main
struct AppleData: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cadence",
        abstract: "Read and write Apple Calendar and Reminders data.",
        subcommands: [Cal.self, Rem.self, Note.self]
    )
}
