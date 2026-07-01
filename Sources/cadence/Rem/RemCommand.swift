import ArgumentParser

struct Rem: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rem",
        abstract: "Reminders operations.",
        subcommands: [RemRead.self, RemCreate.self, RemUpdate.self, RemDone.self, RemFlag.self, RemLists.self, RemDelete.self]
    )
}
