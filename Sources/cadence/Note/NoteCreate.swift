import ArgumentParser
import Foundation

struct NoteCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note."
    )

    @Option(name: .long, help: "Note title.") var title: String
    @Option(name: .long, help: "Note body text.") var body: String?
    @Option(name: .long, help: "Folder name (default: Notes).") var folder: String = "Notes"
    @Flag(name: .long, help: "Output as JSON.") var json: Bool = false
    @Flag(name: .long, help: "Human-readable output (default).") var human: Bool = false

    func run() throws {
        let bodyText = body ?? ""

        // Escape for AppleScript string literals
        let escapedTitle = ScriptRunner.escapeForAppleScript(title)
        let escapedFolder = ScriptRunner.escapeForAppleScript(folder)
        let escapedBody = ScriptRunner.escapeForAppleScript(bodyText)

        let htmlBody = "<html><body><h1>\(escapedTitle)</h1><p>\(escapedBody)</p></body></html>"

        let script = """
        tell application "Notes"
            if not (exists folder "\(escapedFolder)") then
                make new folder with properties {name:"\(escapedFolder)"}
            end if
            tell folder "\(escapedFolder)"
                set newNote to make new note with properties {name:"\(escapedTitle)", body:"\(htmlBody)"}
                return name of newNote
            end tell
        end tell
        """

        let result: String
        do {
            result = try ScriptRunner.osascript(script)
        } catch {
            fputs("AppleScript error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        let noteName = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if json && !human {
            let out: [String: Any] = [
                "title": noteName,
                "folder": folder,
                "status": "created"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Created: \"\(noteName)\" in folder \"\(folder)\"")
        }
    }
}
