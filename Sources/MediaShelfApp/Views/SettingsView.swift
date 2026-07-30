import MediaShelfCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    @Environment(\.dismiss) private var dismiss
    @State private var libraryToRemove: LibraryFolder?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.largeTitle.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(26)
            Divider()
            Form {
                Section("Library") {
                    ForEach(appState.libraries) { library in
                        HStack {
                            Toggle(
                                isOn: Binding(
                                    get: { library.isEnabled },
                                    set: { enabled in
                                        Task {
                                            await appState.setLibraryEnabled(library, enabled: enabled)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading) {
                                    Text(library.displayName)
                                    Text(library.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Button(role: .destructive) {
                                libraryToRemove = library
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove from MediaShelf. Video files are never deleted.")
                        }
                    }
                    HStack {
                        Button("Add Folder…") {
                            appState.chooseAndAddLibrary()
                        }
                        Button("Refresh Library") {
                            Task { await appState.refreshAll() }
                        }
                    }
                }

                Section("Artwork & Metadata") {
                    Toggle(
                        "Automatically match posters and backdrops after scanning",
                        isOn: Binding(
                            get: { appState.automaticArtwork },
                            set: { value in
                                Task { await appState.setAutomaticArtwork(value) }
                            }
                        )
                    )
                    Text("Matches the parsed title and year through the optional Cinemeta provider, then caches images on the portable drive. Manual artwork always wins. Turn this off for strictly offline use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Controller") {
                    LabeledContent("Xbox controller") {
                        Label(
                            controller.isConnected ? "Connected" : "Not connected",
                            systemImage: controller.isConnected ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .foregroundStyle(controller.isConnected ? ShelfTheme.accent : .secondary)
                    }
                    Text("D-pad or left stick navigates, A selects, B opens or closes the sidebar (and goes back from details), X toggles play/pause, and Menu opens controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Playback") {
                    LabeledContent("Native backend", value: "AVFoundation")
                    LabeledContent("Wide-codec backend") {
                        Text("libmpv adapter prepared")
                            .foregroundStyle(.secondary)
                    }
                    Text("MP4, M4V, and MOV use the native player. MKV and advanced audio/subtitle combinations require the redistributable Intel libmpv bundle described in docs/PLAYBACK.md.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Portable Data") {
                    LabeledContent("Location", value: appState.paths.root.path)
                    Button("Open in Finder") {
                        appState.openPortableDataInFinder()
                    }
                }

                Section("Privacy") {
                    Text("No accounts, analytics, telemetry, advertising, or uploads. When automatic artwork is enabled, only the parsed title, media type, and year are sent to the selected metadata provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 690, minHeight: 650)
        .background(ShelfTheme.background)
        .confirmationDialog(
            "Remove \(libraryToRemove?.displayName ?? "this folder") from MediaShelf?",
            isPresented: Binding(
                get: { libraryToRemove != nil },
                set: { if !$0 { libraryToRemove = nil } }
            )
        ) {
            Button("Remove from Library", role: .destructive) {
                if let libraryToRemove {
                    Task { await appState.removeLibrary(libraryToRemove) }
                }
                libraryToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                libraryToRemove = nil
            }
        } message: {
            Text("Indexed entries are removed from the portable database. Media files remain untouched.")
        }
    }
}
