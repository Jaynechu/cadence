import ArgumentParser

struct Cal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cal",
        abstract: "Calendar operations.",
        subcommands: [CalRead.self, CalCreate.self, CalUpdate.self, CalDelete.self]
    )
}
