import MediaShelfCore
import SwiftUI

struct DetailsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    let originalItem: MediaItem
    @State private var showsEditor = false
    @State private var selectedSeason: Int?
    @FocusState private var focusedEpisodeID: String?

    private var item: MediaItem {
        appState.media.first { $0.id == originalItem.id } ?? originalItem
    }

    private var siblingEpisodes: [MediaItem] {
        appState.media
            .filter {
                $0.kind == .episode &&
                $0.displayTitle.caseInsensitiveCompare(item.displayTitle) == .orderedSame
            }
            .sorted {
                ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) <
                ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
            }
    }

    private var seasons: [Int] {
        Array(Set(siblingEpisodes.map { $0.seasonNumber ?? 0 })).sorted()
    }

    private var visibleEpisodes: [MediaItem] {
        guard let selectedSeason else { return siblingEpisodes }
        return siblingEpisodes.filter { ($0.seasonNumber ?? 0) == selectedSeason }
    }

    var body: some View {
        ZStack {
            ShelfTheme.ambientBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if item.kind == .episode {
                        episodeBrowser
                    }
                }
            }
            VStack {
                HStack {
                    Button {
                        appState.selectedItem = nil
                    } label: {
                        Label("Back to Browse", systemImage: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight: 650)
        .sheet(isPresented: $showsEditor) {
            MetadataEditorView(appState: appState, item: item)
        }
        .onAppear {
            if selectedSeason == nil {
                selectedSeason = item.seasonNumber ?? seasons.first
            }
        }
        .onChange(of: controller.actionRevision) { _ in
            guard let action = controller.lastAction else { return }
            switch action {
            case .select:
                if let focusedEpisodeID,
                   let episode = siblingEpisodes.first(where: { $0.id == focusedEpisodeID }) {
                    appState.playingItem = episode
                } else {
                    appState.playingItem = item
                }
            case .down:
                moveEpisodeFocus(by: 1)
            case .up:
                moveEpisodeFocus(by: -1)
            default:
                break
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(
                path: item.backdropPath ?? item.posterPath,
                title: item.displayTitle,
                isBackdrop: true
            )
            .frame(height: 600)
            .overlay {
                LinearGradient(
                    colors: [.clear, ShelfTheme.background.opacity(0.30), ShelfTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    colors: [ShelfTheme.background.opacity(0.93), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                appState.importArtwork(from: url, for: item, role: .backdrop)
                return true
            }

            HStack(alignment: .bottom, spacing: 30) {
                ArtworkView(path: item.posterPath, title: item.displayTitle)
                    .frame(width: 210, height: 315)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12))
                    }
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        appState.importArtwork(from: url, for: item, role: .poster)
                        return true
                    }
                    .contextMenu {
                        artworkMenu
                    }

                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 12) {
                        if let year = item.year {
                            Text(String(year))
                        }
                        if let runtime = item.runtime {
                            Text(duration(runtime))
                        }
                        if let genre = item.genre {
                            Text(genre)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShelfTheme.textSecondary)
                    Text(item.displayTitle)
                        .font(.system(size: 52, weight: .semibold))
                        .tracking(-1.2)
                        .lineLimit(2)
                    if item.kind == .episode {
                        Text("\(item.episodeCode) • \(item.effectiveEpisodeTitle)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ShelfTheme.accent)
                    }
                    Text(item.summary ?? "No description yet. Use Edit Details to add one.")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(5)
                        .lineSpacing(3)
                        .frame(maxWidth: 650, alignment: .leading)
                    controls
                }
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 30)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Button {
                    appState.playingItem = item
                } label: {
                    Label(item.continueWatching ? "Resume" : "Play", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                if item.playbackPosition > 0 {
                    Button {
                        Task { await appState.restart(item) }
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button {
                    Task { await appState.toggleFavorite(item) }
                } label: {
                    Label(
                        item.isFavorite ? "Favorited" : "Favorite",
                        systemImage: item.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: 18) {
                Menu("Artwork") {
                    artworkMenu
                }
                Button("Edit Details…") {
                    showsEditor = true
                }
                Button("Show in Finder") {
                    appState.showMediaInFinder(item)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ShelfTheme.accent)
        }
    }

    @ViewBuilder
    private var artworkMenu: some View {
        Button("Choose Poster…") {
            appState.chooseArtwork(for: item, role: .poster)
        }
        Button("Choose Backdrop…") {
            appState.chooseArtwork(for: item, role: .backdrop)
        }
        Divider()
        Button("Remove Poster") {
            Task { await appState.removeArtwork(from: item, role: .poster) }
        }
        .disabled(item.posterPath == nil)
        Button("Remove Backdrop") {
            Task { await appState.removeArtwork(from: item, role: .backdrop) }
        }
        .disabled(item.backdropPath == nil)
    }

    private var episodeBrowser: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Episodes")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { season in
                        Text("Season \(season)").tag(Optional(season))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            LazyVStack(spacing: 12) {
                ForEach(visibleEpisodes) { episode in
                    EpisodeRow(
                        item: episode,
                        focusedEpisode: $focusedEpisodeID
                    ) {
                        appState.playingItem = episode
                    }
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 50)
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func moveEpisodeFocus(by offset: Int) {
        guard !siblingEpisodes.isEmpty else { return }
        guard let currentEpisodeID = focusedEpisodeID,
              let current = siblingEpisodes.firstIndex(where: { $0.id == currentEpisodeID }) else {
            self.focusedEpisodeID = offset < 0 ? siblingEpisodes.last?.id : siblingEpisodes.first?.id
            return
        }
        let next = min(max(current + offset, 0), siblingEpisodes.count - 1)
        focusedEpisodeID = siblingEpisodes[next].id
    }
}

private struct EpisodeRow: View {
    let item: MediaItem
    var focusedEpisode: FocusState<String?>.Binding
    let play: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: play) {
            HStack(spacing: 18) {
                ArtworkView(
                    path: item.thumbnailPath ?? item.backdropPath ?? item.posterPath,
                    title: item.effectiveEpisodeTitle,
                    isBackdrop: true
                )
                .frame(width: 190, height: 106)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(episodeTitle)
                        .font(.headline)
                    Text(item.summary ?? item.filename)
                        .font(.subheadline)
                        .foregroundStyle(ShelfTheme.textSecondary)
                        .lineLimit(2)
                    if item.progressFraction > 0 {
                        ProgressView(value: item.progressFraction)
                            .tint(ShelfTheme.accent)
                            .frame(maxWidth: 320)
                    }
                }
                Spacer()
                Image(systemName: item.continueWatching ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(ShelfTheme.accent)
            }
            .padding(12)
            .background(isFocused ? ShelfTheme.surfaceRaised : ShelfTheme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.88) : ShelfTheme.hairline, lineWidth: isFocused ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused(focusedEpisode, equals: item.id)
    }

    private var episodeTitle: String {
        if let number = item.episodeNumber {
            return "\(number). \(item.effectiveEpisodeTitle)"
        }
        return item.effectiveEpisodeTitle
    }
}

struct MetadataEditorView: View {
    @ObservedObject var appState: AppState
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var year: String
    @State private var summary: String
    @State private var genre: String
    @State private var runtimeMinutes: String
    @State private var episodeTitle: String

    init(appState: AppState, item: MediaItem) {
        self.appState = appState
        self.item = item
        _title = State(initialValue: item.displayTitle)
        _year = State(initialValue: item.year.map(String.init) ?? "")
        _summary = State(initialValue: item.summary ?? "")
        _genre = State(initialValue: item.genre ?? "")
        _runtimeMinutes = State(initialValue: item.runtime.map { String(Int($0 / 60)) } ?? "")
        _episodeTitle = State(initialValue: item.episodeTitle ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Details")
                .font(.title.bold())
            Form {
                TextField(item.kind == .movie ? "Title" : "Series title", text: $title)
                TextField("Year", text: $year)
                if item.kind == .episode {
                    TextField("Episode title", text: $episodeTitle)
                }
                TextField("Genre", text: $genre)
                TextField("Runtime (minutes)", text: $runtimeMinutes)
                TextField("Description", text: $summary, axis: .vertical)
                    .lineLimit(5...10)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        await appState.updateMetadata(
                            item,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            year: Int(year),
                            summary: summary.isEmpty ? nil : summary,
                            genre: genre.isEmpty ? nil : genre,
                            runtime: Double(runtimeMinutes).map { $0 * 60 },
                            episodeTitle: episodeTitle.isEmpty ? nil : episodeTitle
                        )
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 560)
    }
}
