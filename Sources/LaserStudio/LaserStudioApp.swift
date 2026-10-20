import SwiftUI

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("LaserStudio Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
            Button("Instruction Manual") { openWindow(id: "manual") }
        }
    }
}

@main
struct LaserStudioApp: App {
    var body: some Scene {
        WindowGroup("LaserStudio") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        Window("LaserStudio Help", id: "help") { HelpInfoView() }
        Window("LaserStudio Instruction Manual", id: "manual") { ManualView() }
        .commands {
            HelpCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Project") { NotificationCenter.default.post(name: .newProject, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Export G-code…") { NotificationCenter.default.post(name: .exportJob, object: nil) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newProject = Notification.Name("newProject")
    static let exportJob = Notification.Name("exportJob")
}
