import MediaShelfCore
import SwiftUI

struct LibraryShellView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            LibraryHomeView(appState: appState, controller: controller)
        }
        .tint(ShelfTheme.accent)
    }

    private var sidebar: some View {
        List(selection: $appState.selectedFilter) {
            Section {
                ForEach(MediaFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: icon(for: filter))
                        .tag(filter)
                }
            }
            Section("Library folders") {
                ForEach(appState.libraries) { library in
                    HStack {
                        Image(systemName: library.availability == .available ? "externaldrive.fill" : "externaldrive.badge.exclamationmark")
                        Text(library.displayName)
                            .lineLimit(1)
                        Spacer()
                        if !library.isEnabled {
                            Text("Off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    appState.chooseAndAddLibrary()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                appState.showsSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if controller.isConnected {
                Label("Controller connected", systemImage: "gamecontroller.fill")
                    .font(.caption)
                    .foregroundStyle(ShelfTheme.accent)
                    .padding(12)
            }
        }
    }

    private func icon(for filter: MediaFilter) -> String {
        switch filter {
        case .all: "house.fill"
        case .movies: "film.fill"
        case .tvShows: "tv.fill"
        case .watched: "checkmark.circle.fill"
        case .unwatched: "circle"
        case .favorites: "heart.fill"
        }
    }
}

struct LibraryHomeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    private let columns = [GridItem(.adaptive(minimum: 178, maximum: 205), spacing: 26)]

    var body: some View {
        ZStack {
            ShelfTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    header
                    if appState.searchText.isEmpty && appState.selectedFilter == .all {
                        hero
                        if !appState.continueWatching.isEmpty {
                            MediaShelfRow(
                                title: "Continue Watching",
                                items: appState.continueWatching,
                                appState: appState
                            )
                        }
                        if !appState.recentlyAdded.isEmpty {
                            MediaShelfRow(
                                title: "Recently Added",
                                items: appState.recentlyAdded,
                                episodesAreSeries: true,
                                appState: appState
                            )
                        }
                        if !appState.movies.isEmpty {
                            MediaShelfRow(
                                title: "Movies",
                                items: Array(appState.movies.prefix(20)),
                                appState: appState
                            )
                        }
                        if !appState.series.isEmpty {
                            MediaShelfRow(
                                title: "TV Shows",
                                items: appState.series.compactMap(\.representative),
                                episodesAreSeries: true,
                                appState: appState
                            )
                        }
                    } else {
                        filteredGrid
                    }
                }
                .padding(.bottom, 54)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isBusy)
                Picker("Sort", selection: $appState.selectedSort) {
                    ForEach(MediaSort.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 155)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.selectedFilter == .all ? "MediaShelf" : appState.selectedFilter.rawValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(appState.media.count) videos • \(appState.libraries.count) \(appState.libraries.count == 1 ? "folder" : "folders")")
                    .foregroundStyle(ShelfTheme.textSecondary)
            }
            Spacer()
            if appState.isMatchingArtwork {
                Label("Matching artwork", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShelfTheme.accent)
            }
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search your library", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 240)
                if !appState.searchText.isEmpty {
                    Button {
                        appState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 34)
        .padding(.top, 22)
    }

    @ViewBuilder
    private var hero: some View {
        if let item = appState.continueWatching.first ?? appState.recentlyAdded.first {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(
                    path: item.backdropPath ?? item.posterPath,
                    title: item.displayTitle,
                    isBackdrop: true
                )
                .frame(height: 390)
                .overlay {
                    LinearGradient(
                        colors: [.clear, ShelfTheme.background.opacity(0.32), ShelfTheme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [ShelfTheme.background.opacity(0.92), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.kind == .movie ? "FEATURED MOVIE" : "UP NEXT")
                        .font(.caption.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(ShelfTheme.accent)
                    Text(item.displayTitle)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    if let summary = item.summary {
                        Text(summary)
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineLimit(3)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                    HStack {
                        Button {
                            appState.playingItem = item
                        } label: {
                            Label(item.continueWatching ? "Resume" : "Play", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button {
                            appState.selectedItem = item
                        } label: {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(38)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 34)
        }
    }

    private var filteredGrid: some View {
        Group {
            if appState.filteredCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42))
                        .foregroundStyle(ShelfTheme.textSecondary)
                    Text("Nothing here")
                        .font(.title2.bold())
                    Text("Try another filter or search term.")
                        .foregroundStyle(ShelfTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(appState.filteredCards) { item in
                        PosterCard(item: item, treatEpisodeAsSeries: item.kind == .episode) {
                            appState.selectedItem = item
                        }
                    }
                }
                .padding(.horizontal, 34)
            }
        }
    }
}

struct MediaShelfRow: View {
    let title: String
    let items: [MediaItem]
    var episodesAreSeries = false
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 34)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(items) { item in
                        PosterCard(
                            item: item,
                            treatEpisodeAsSeries: episodesAreSeries && item.kind == .episode
                        ) {
                            appState.selectedItem = item
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 8)
            }
        }
    }
}
