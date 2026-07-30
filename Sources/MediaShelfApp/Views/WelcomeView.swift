import SwiftUI

struct WelcomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            ShelfTheme.background.ignoresSafeArea()
            LinearGradient(
                colors: [
                    ShelfTheme.secondaryAccent.opacity(0.2),
                    Color.clear,
                    ShelfTheme.accent.opacity(0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [ShelfTheme.accent, ShelfTheme.secondaryAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 116, height: 116)
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.78))
                }
                Text("Your library. Anywhere.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("Choose one or more folders and MediaShelf will build a private,\noffline library without moving or changing a single video.")
                    .font(.title3)
                    .foregroundStyle(ShelfTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Button {
                    appState.chooseAndAddLibrary()
                } label: {
                    Label("Choose Media Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 22) {
                    Label("Portable data", systemImage: "externaldrive")
                    Label("Automatic posters", systemImage: "photo.on.rectangle")
                    Label("Xbox controller ready", systemImage: "gamecontroller")
                    Label("No account", systemImage: "person.crop.circle.badge.xmark")
                }
                .font(.caption)
                .foregroundStyle(ShelfTheme.textSecondary)
                .padding(.top, 8)
            }
            .padding(50)
        }
    }
}
