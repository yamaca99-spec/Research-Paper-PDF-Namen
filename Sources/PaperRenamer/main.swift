import Foundation

let launchArguments = Array(CommandLine.arguments.dropFirst())

if launchArguments.first == "--cli" {
    // Headless mode: print (and optionally apply) the proposed names, then exit.
    let cliArguments = Array(launchArguments.dropFirst())
    Task.detached { [cliArguments] in
        let code = await CLI.run(arguments: cliArguments)
        exit(code)
    }
    dispatchMain()
} else {
    PaperRenamerApp.main()
}
