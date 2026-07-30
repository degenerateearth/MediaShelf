import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager

    var body: some View {
        ZStack {
            Group {
                if appState.hasLibrary {
                    LibraryShellView(appState: appState, controller: controller)
                } else {
                    WelcomeView(appState: appState)
                }
            }
            if appState.isBusy {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(appState.activityText)
                        .font(.headline)
                }
                .padding(26)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 25)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await appState.bootstrap()
        }
        .sheet(item: $appState.selectedItem) { item in
            DetailsView(appState: appState, originalItem: item)
        }
        .sheet(item: $appState.playingItem) { item in
            PlayerView(appState: appState, controller: controller, item: item)
        }
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView(appState: appState, controller: controller)
        }
        .alert(
            "MediaShelf",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .onChange(of: controller.lastAction) { action in
            guard let action else { return }
            if action == .menu && appState.playingItem == nil {
                appState.showsSettings.toggle()
                controller.consume()
            }
            if action == .back && appState.playingItem == nil {
                if appState.selectedItem != nil {
                    appState.selectedItem = nil
                } else if appState.showsSettings {
                    appState.showsSettings = false
                } else {
                    appState.toggleSidebar()
                }
                controller.consume()
            }
        }
    }
}
