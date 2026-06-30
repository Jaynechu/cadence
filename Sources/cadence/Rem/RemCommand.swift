import ArgumentParser

struct Rem: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rem",
        abstract: "Reminders operations.",
        subcommands: [RemRead.self, RemCreate.self, RemDone.self, RemFlag.self, RemLists.self, RemDelete.self]
    )
}
