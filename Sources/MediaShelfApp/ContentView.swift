import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager

    var body: some View {
        ZStack {
            Group {
                if let playingItem = appState.playingItem {
                    PlayerView(
                        appState: appState,
                        controller: controller,
                        item: playingItem
                    )
                    .id(playingItem.id)
                    .transition(.opacity)
                } else if let selectedItem = appState.selectedItem {
                    DetailsView(
                        appState: appState,
                        controller: controller,
                        originalItem: selectedItem
                    )
                    .id(selectedItem.id)
                    .transition(.opacity)
                } else if appState.hasLibrary {
                    LibraryShellView(appState: appState, controller: controller)
                } else {
                    WelcomeView(appState: appState)
                }
            }
            if appState.isBusy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(appState.activityText)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(ShelfTheme.hairline) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(22)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await appState.bootstrap()
        }
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView(appState: appState, controller: controller)
        }
        .sheet(isPresented: $appState.showsArtworkReview) {
            ArtworkMatchView(appState: appState)
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
        .onChange(of: controller.actionRevision) { _ in
            guard let action = controller.lastAction else { return }
            if action == .menu && appState.playingItem == nil {
                appState.showsSettings.toggle()
            }
            if action == .back && appState.playingItem == nil {
                if appState.selectedItem != nil {
                    appState.selectedItem = nil
                } else if appState.showsSettings {
                    appState.showsSettings = false
                } else {
                    appState.toggleSidebar()
                }
            }
        }
    }
}
