import SwiftUI

@main
struct LaserStudioApp: App {
    var body: some Scene {
        WindowGroup("LaserStudio") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        .commands {
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
