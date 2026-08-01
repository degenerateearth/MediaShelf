import MediaShelfCore
import SwiftUI

struct LibraryShellView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            LibraryHomeView(appState: appState, controller: controller)
        }
        .tint(ShelfTheme.accent)
        .onChange(of: appState.selectedFilter) { _ in
            appState.sidebarVisibility = .detailOnly
        }
        .onChange(of: controller.actionRevision) { _ in
            guard appState.sidebarVisibility != .detailOnly,
                  let action = controller.lastAction else { return }
            switch action {
            case .up:
                moveSidebarSelection(by: -1)
            case .down:
                moveSidebarSelection(by: 1)
            case .right, .select:
                appState.sidebarVisibility = .detailOnly
            default:
                break
            }
        }
    }

    private var sidebar: some View {
        List(selection: $appState.selectedFilter) {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MEDIA")
                        .font(.caption2.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(ShelfTheme.accent)
                    Text("My Library")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ShelfTheme.textPrimary)
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
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
            Section("Artwork") {
                Button {
                    Task { await appState.findMissingArtwork() }
                } label: {
                    Label(
                        appState.isMatchingArtwork ? "Finding Artwork…" : "Get Missing Artwork",
                        systemImage: "sparkles.rectangle.stack"
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.isMatchingArtwork)
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
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
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

    private func moveSidebarSelection(by offset: Int) {
        let filters = MediaFilter.allCases
        guard let current = filters.firstIndex(of: appState.selectedFilter) else {
            appState.selectedFilter = .all
            return
        }
        appState.selectedFilter = filters[
            min(max(current + offset, filters.startIndex), filters.index(before: filters.endIndex))
        ]
    }
}

private enum ControllerDestination {
    case play(MediaItem)
    case details(MediaItem)
    case media(MediaItem)
}

private struct ControllerNavigationEntry {
    let id: String
    let destination: ControllerDestination
}

private struct ControllerNavigationRow {
    let id: String
    let entries: [ControllerNavigationEntry]
}

struct LibraryHomeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ControllerManager
    private let columns = [GridItem(.adaptive(minimum: 178, maximum: 205), spacing: 26)]
    @State private var focusedCardID: String?

    var body: some View {
        ZStack {
            ShelfTheme.ambientBackground.ignoresSafeArea()
            ScrollViewReader { pageProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 40) {
                        header
                        if appState.searchText.isEmpty && appState.selectedFilter == .all {
                            hero
                                .id("row:hero")
                            if !appState.continueWatching.isEmpty {
                                MediaShelfRow(
                                    title: "Continue Watching",
                                    items: appState.continueWatching,
                                    focusGroup: "continue",
                                    focusedCard: $focusedCardID,
                                    canMarkFinished: true,
                                    appState: appState
                                )
                                .id("row:continue")
                            }
                            if !appState.movies.isEmpty {
                                MediaShelfRow(
                                    title: "Movies",
                                    items: Array(appState.movies.prefix(20)),
                                    focusGroup: "movies",
                                    focusedCard: $focusedCardID,
                                    appState: appState
                                )
                                .id("row:movies")
                            }
                            if !appState.series.isEmpty {
                                MediaShelfRow(
                                    title: "TV Shows",
                                    items: appState.series.compactMap(\.representative),
                                    episodesAreSeries: true,
                                    focusGroup: "tv",
                                    focusedCard: $focusedCardID,
                                    appState: appState
                                )
                                .id("row:tv")
                            }
                            ForEach(appState.genreShelves) { shelf in
                                MediaShelfRow(
                                    title: shelf.name,
                                    items: shelf.items,
                                    episodesAreSeries: true,
                                    focusGroup: "genre:\(shelf.id)",
                                    focusedCard: $focusedCardID,
                                    appState: appState
                                )
                                .id("row:genre:\(shelf.id)")
                            }
                            if !appState.recentlyAdded.isEmpty {
                                MediaShelfRow(
                                    title: "Recently Added",
                                    items: appState.recentlyAdded,
                                    episodesAreSeries: true,
                                    focusGroup: "recent",
                                    focusedCard: $focusedCardID,
                                    appState: appState
                                )
                                .id("row:recent")
                            }
                        } else {
                            filteredGrid
                        }
                    }
                    .padding(.bottom, 54)
                }
                .onChange(of: focusedCardID) { focusID in
                    guard let focusID,
                          let row = controllerRows.first(where: {
                              $0.entries.contains(where: { $0.id == focusID })
                          }) else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if row.id.hasPrefix("filtered-") {
                            pageProxy.scrollTo(focusID, anchor: .center)
                        } else {
                            pageProxy.scrollTo("row:\(row.id)", anchor: .center)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(appState.selectedFilter == .all ? "MediaShelf" : appState.selectedFilter.rawValue)
                    .font(.system(size: 15, weight: .semibold))
            }
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
        .onAppear {
            resetControllerFocus()
        }
        .onChange(of: appState.selectedFilter) { _ in
            resetControllerFocus()
        }
        .onChange(of: appState.searchText) { _ in
            resetControllerFocus()
        }
        .onChange(of: appState.media.count) { _ in
            resetControllerFocus()
        }
        .onChange(of: controller.actionRevision) { _ in
            handleControllerAction()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                handleNavigationAction(.left)
            case .right:
                handleNavigationAction(.right)
            case .up:
                handleNavigationAction(.up)
            case .down:
                handleNavigationAction(.down)
            default:
                break
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.selectedFilter == .all ? "MediaShelf" : appState.selectedFilter.rawValue)
                    .font(.system(size: 32, weight: .semibold))
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
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(ShelfTheme.hairline) }
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
                .frame(height: 500)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, ShelfTheme.canvas.opacity(0.15), ShelfTheme.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [ShelfTheme.canvas.opacity(0.98), ShelfTheme.canvas.opacity(0.55), .clear],
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
                        .font(.system(size: 52, weight: .semibold))
                        .tracking(-1.2)
                        .lineLimit(2)
                    if let summary = item.summary {
                        Text(summary)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(0.72))
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
                        .focusable()
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(focusedCardID == "hero::play" ? Color.white : .clear, lineWidth: 3)
                        }
                        .scaleEffect(focusedCardID == "hero::play" ? 1.06 : 1)
                        Button {
                            appState.selectedItem = item
                        } label: {
                            Label("Details", systemImage: "info.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .focusable()
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(focusedCardID == "hero::details" ? ShelfTheme.accent : .clear, lineWidth: 3)
                        }
                        .scaleEffect(focusedCardID == "hero::details" ? 1.06 : 1)
                    }
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 46)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [ShelfTheme.canvas.opacity(0.48), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
            }
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
                    ForEach(Array(appState.filteredCards.enumerated()), id: \.element.id) { index, item in
                        PosterCard(
                            item: item,
                            treatEpisodeAsSeries: item.kind == .episode,
                            focusID: focusToken(group: "filtered-\(index / 5)", item: item),
                            focusedCard: $focusedCardID
                        ) {
                            appState.selectedItem = item
                        }
                    }
                }
                .padding(.horizontal, 34)
            }
        }
    }

    private var controllerRows: [ControllerNavigationRow] {
        if appState.searchText.isEmpty && appState.selectedFilter == .all {
            var rows: [ControllerNavigationRow] = []
            if let item = appState.continueWatching.first ?? appState.recentlyAdded.first {
                rows.append(.init(
                    id: "hero",
                    entries: [
                        .init(id: "hero::play", destination: .play(item)),
                        .init(id: "hero::details", destination: .details(item))
                    ]
                ))
            }
            if !appState.continueWatching.isEmpty {
                rows.append(mediaNavigationRow(id: "continue", items: appState.continueWatching))
            }
            if !appState.movies.isEmpty {
                rows.append(mediaNavigationRow(id: "movies", items: Array(appState.movies.prefix(20))))
            }
            let shows = appState.series.compactMap(\.representative)
            if !shows.isEmpty {
                rows.append(mediaNavigationRow(id: "tv", items: shows))
            }
            rows.append(contentsOf: appState.genreShelves.map {
                mediaNavigationRow(id: "genre:\($0.id)", items: $0.items)
            })
            if !appState.recentlyAdded.isEmpty {
                rows.append(mediaNavigationRow(id: "recent", items: appState.recentlyAdded))
            }
            return rows
        }

        return stride(from: 0, to: appState.filteredCards.count, by: 5).map { start in
            let end = min(start + 5, appState.filteredCards.count)
            return mediaNavigationRow(
                id: "filtered-\(start / 5)",
                items: Array(appState.filteredCards[start..<end])
            )
        }
    }

    private func mediaNavigationRow(id: String, items: [MediaItem]) -> ControllerNavigationRow {
        .init(
            id: id,
            entries: items.map {
                .init(id: focusToken(group: id, item: $0), destination: .media($0))
            }
        )
    }

    private func focusToken(group: String, item: MediaItem) -> String {
        "\(group)::\(item.id)"
    }

    private func resetControllerFocus() {
        guard let entry = controllerRows.first?.entries.first else {
            focusedCardID = nil
            return
        }
        focusedCardID = entry.id
    }

    private func handleControllerAction() {
        guard appState.sidebarVisibility == .detailOnly,
              let action = controller.lastAction else { return }
        handleNavigationAction(action)
    }

    private func handleNavigationAction(_ action: ControllerAction) {
        switch action {
        case .left:
            moveControllerFocus(horizontal: -1)
        case .right:
            moveControllerFocus(horizontal: 1)
        case .up:
            moveControllerFocus(vertical: -1)
        case .down:
            moveControllerFocus(vertical: 1)
        case .select:
            switch focusedControllerDestination {
            case .play(let item):
                appState.playingItem = item
            case .details(let item), .media(let item):
                appState.selectedItem = item
            case nil:
                resetControllerFocus()
            }
        default:
            break
        }
    }

    private var focusedControllerLocation: (row: Int, column: Int)? {
        guard let focusedCardID else { return nil }
        for (rowIndex, row) in controllerRows.enumerated() {
            if let column = row.entries.firstIndex(where: { $0.id == focusedCardID }) {
                return (rowIndex, column)
            }
        }
        return nil
    }

    private var focusedControllerDestination: ControllerDestination? {
        guard let location = focusedControllerLocation else { return nil }
        return controllerRows[location.row].entries[location.column].destination
    }

    private func moveControllerFocus(horizontal offset: Int) {
        guard !controllerRows.isEmpty else { return }
        guard let location = focusedControllerLocation else {
            resetControllerFocus()
            return
        }
        let row = controllerRows[location.row]
        let column = min(max(location.column + offset, 0), row.entries.count - 1)
        focusedCardID = row.entries[column].id
    }

    private func moveControllerFocus(vertical offset: Int) {
        guard !controllerRows.isEmpty else { return }
        guard let location = focusedControllerLocation else {
            resetControllerFocus()
            return
        }
        let rowIndex = min(max(location.row + offset, 0), controllerRows.count - 1)
        let row = controllerRows[rowIndex]
        let column = min(location.column, row.entries.count - 1)
        focusedCardID = row.entries[column].id
    }
}

struct MediaShelfRow: View {
    let title: String
    let items: [MediaItem]
    var episodesAreSeries = false
    let focusGroup: String
    @Binding var focusedCard: String?
    var canMarkFinished = false
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 23, weight: .semibold))
                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShelfTheme.textTertiary)
            }
                .padding(.horizontal, 34)
            shelfScroller
        }
    }

    private var shelfScroller: some View {
        ScrollViewReader { rowProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(items) { item in
                        shelfCard(item)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 8)
            }
            .onChange(of: focusedCard) { focusID in
                guard let focusID, focusID.hasPrefix("\(focusGroup)::") else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    rowProxy.scrollTo(focusID, anchor: .center)
                }
            }
            .onAppear {
                guard let focusID = focusedCard,
                      focusID.hasPrefix("\(focusGroup)::") else { return }
                rowProxy.scrollTo(focusID, anchor: .center)
            }
        }
    }

    private func shelfCard(_ item: MediaItem) -> some View {
        PosterCard(
            item: item,
            treatEpisodeAsSeries: episodesAreSeries && item.kind == .episode,
            focusID: "\(focusGroup)::\(item.id)",
            focusedCard: $focusedCard,
            markFinished: canMarkFinished ? {
                Task { await appState.markFinished(item) }
            } : nil
        ) {
            appState.selectedItem = item
        }
    }
}
