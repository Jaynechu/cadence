import ArgumentParser

struct Note: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Notes operations.",
        subcommands: [NoteList.self, NoteRead.self, NoteCreate.self, NoteWrite.self, NoteDelete.self]
    )
}
