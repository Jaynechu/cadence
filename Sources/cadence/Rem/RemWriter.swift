import Foundation

enum RemWriter {
    // EventKit has no all-day concept for reminders; the flag only exists in the
    // Reminders CoreData store, so it has to be written there after the save.
    static func setAllDay(uid: String, isDateOnly: Bool) {
        let flag = isDateOnly ? 1 : 0
        try? SQLiteDB.executeRW(
            path: DBPath.reminders,
            sql: "UPDATE ZREMCDREMINDER SET ZALLDAY = ?, ZDISPLAYDATEISALLDAY = ? WHERE ZDACALENDARITEMUNIQUEIDENTIFIER = ?",
            bindings: [flag, flag, uid])
    }
}
