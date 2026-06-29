import ArgumentParser
import Foundation

struct NoteRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read full body of a note by its ID (Z_PK from note list)."
    )

    @Argument(help: "Note ID (Z_PK from note list).") var id: Int

    @Flag(name: .long, help: "Output as JSON.") var json: Bool = false
    @Flag(name: .long, help: "Human-readable output (default).") var human: Bool = false

    func run() throws {
        let db = try SQLiteDB(path: DBPath.notes)

        let rows = try db.query(
            """
            SELECT n.Z_PK as id, n.ZTITLE1 as title, n.ZIDENTIFIER as identifier,
                   f.ZTITLE2 as folder_name
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.Z_ENT = 12 AND n.Z_PK = \(id)
            LIMIT 1
            """
        )

        guard let row = rows.first, let title = row["title"] as? String else {
            fputs("Note ID \(id) not found.\n", stderr)
            throw ExitCode.failure
        }

        let folderName = row["folder_name"] as? String ?? ""

        // Fail early if multiple notes share this title
        let dups = try db.query(
            """
            SELECT n.Z_PK as id, f.ZTITLE2 as folder_name
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.Z_ENT = 12 AND n.ZTITLE1 = ? AND n.ZMARKEDFORDELETION = 0
            """,
            bindings: [title]
        )
        if dups.count > 1 {
            fputs("Ambiguous: \(dups.count) notes share title \"\(title)\":\n", stderr)
            for dup in dups {
                let did = dup["id"] as? Int64 ?? 0
                let df = dup["folder_name"] as? String ?? "?"
                fputs("  id=\(did) folder=\"\(df)\"\n", stderr)
            }
            throw ExitCode.failure
        }

        // Use AppleScript to fetch full body by title
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            set noteList to every note whose name is "\(escapedTitle)"
            if (count of noteList) > 0 then
                set n to item 1 of noteList
                return body of n
            else
                return ""
            end if
        end tell
        """

        let bodyHTML: String
        do {
            bodyHTML = try ScriptRunner.osascript(script)
        } catch {
            fputs("AppleScript error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        if json && !human {
            let out: [String: Any] = [
                "id": id,
                "title": title,
                "folder": folderName,
                "body": bodyHTML
            ]
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Title:  \(title)")
            print("Folder: \(folderName)")
            print("---")
            print(stripHTML(bodyHTML))
        }
    }

    func stripHTML(_ html: String) -> String {
        // Remove tags, decode basic entities
        var result = html
        // Remove style/script blocks
        let blockPatterns = ["<style[^>]*>.*?</style>", "<script[^>]*>.*?</script>"]
        for pattern in blockPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        // Replace block-level tags with newlines
        let newlineTagPatterns = ["</p>", "<br\\s*/?>", "</div>", "</h[1-6]>", "<li[^>]*>"]
        for pattern in newlineTagPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n")
            }
        }
        // Strip remaining tags
        if let re = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        // Collapse 3+ newlines to 2
        if let re = try? NSRegularExpression(pattern: "\n{3,}", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
