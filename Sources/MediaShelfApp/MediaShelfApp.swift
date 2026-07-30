import SwiftUI

@main
struct MediaShelfApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var controller = ControllerManager()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, controller: controller)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Media Folder…") {
                    appState.chooseAndAddLibrary()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandMenu("Library") {
                Button("Refresh Library") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Settings…") {
                    appState.showsSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
