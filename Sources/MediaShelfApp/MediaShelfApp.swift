import AppKit
import SwiftUI

final class MediaShelfAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MediaShelfApp: App {
    @NSApplicationDelegateAdaptor(MediaShelfAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var controller = ControllerManager()

    var body: some Scene {
        Window("MediaShelf", id: "main") {
            ContentView(appState: appState, controller: controller)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1600, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button("Quit MediaShelf") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
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
                Button("Get Missing Artwork") {
                    Task { await appState.findMissingArtwork() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(appState.isMatchingArtwork)
                Divider()
                Button("Settings…") {
                    appState.showsSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
