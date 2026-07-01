import Foundation

enum DateUtil {
    // Change this identifier for your locale
    static let melbourneTZ = TimeZone(identifier: "Australia/Melbourne")!

    static func fromCoreData(_ timestamp: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: timestamp)
    }

    static func toCoreData(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
    }

    // Reminders stores ZDUEDATE/ZSTARTDATE as floating local wall-clock time:
    // the raw timestamp is the local (Melbourne) clock reading, encoded as if it were UTC.
    // fromCoreData()/formatISO() alone would double-count the Melbourne offset.
    // This corrects a raw CoreData timestamp back to a true absolute Date before formatting.
    static func formatISOFromLocalCoreData(_ ts: Double) -> String {
        let rawDate = fromCoreData(ts)
        let offset = melbourneTZ.secondsFromGMT(for: rawDate)
        let corrected = rawDate.addingTimeInterval(-Double(offset))
        return formatISO(corrected)
    }

    // Inverse of formatISOFromLocalCoreData: given a true absolute Date, produce the
    // raw CoreData-style timestamp using the same "local wall clock as UTC" convention
    // Reminders uses for ZDUEDATE/ZSTARTDATE. Needed for SQL range filters that compare
    // against those raw columns.
    static func toLocalCoreData(_ date: Date) -> Double {
        let offset = melbourneTZ.secondsFromGMT(for: date)
        let naiveDate = date.addingTimeInterval(Double(offset))
        return toCoreData(naiveDate)
    }

    static func formatISO(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = melbourneTZ
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func formatHuman(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = melbourneTZ
        return f.string(from: date)
    }

    static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd (EEE)"
        f.timeZone = melbourneTZ
        return f.string(from: date)
    }

    static func parseInput(_ str: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = melbourneTZ
        f.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = f.date(from: str) { return d }
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: str) { return d }
        return nil
    }

    static func startOfDay(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = melbourneTZ
        return cal.startOfDay(for: date)
    }

    static func endOfDay(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = melbourneTZ
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
    }

    static func todayStart() -> Date {
        startOfDay(Date())
    }

    static func todayEnd() -> Date {
        endOfDay(Date())
    }

    // Returns start of day for a YYYY-MM-DD string
    static func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = melbourneTZ
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }

    static func dateComponentsInMelbourne(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = melbourneTZ
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    static func dateOnlyComponentsInMelbourne(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = melbourneTZ
        return cal.dateComponents([.year, .month, .day], from: date)
    }

    static func isDateOnly(_ str: String) -> Bool {
        str.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func smartComponents(_ str: String) -> DateComponents? {
        guard let date = parseInput(str) else { return nil }
        return isDateOnly(str) ? dateOnlyComponentsInMelbourne(date) : dateComponentsInMelbourne(date)
    }
}
