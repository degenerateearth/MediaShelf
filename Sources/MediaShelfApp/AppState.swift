import AppKit
import Foundation
import MediaShelfCore
import SwiftUI
import UniformTypeIdentifiers

struct GenreShelf: Identifiable {
    let name: String
    let items: [MediaItem]
    var id: String { name.lowercased() }
}

@MainActor
final class AppState: ObservableObject {
    let paths: PortablePaths
    let database: LibraryDatabase
    let scanner: MediaScanner
    let artworkService: ArtworkService
    let metadataArtworkService: MetadataArtworkService
    let metadataProvider: any MetadataProvider

    @Published var libraries: [LibraryFolder] = []
    @Published var media: [MediaItem] = []
    @Published var selectedFilter: MediaFilter = .all
    @Published var selectedSort: MediaSort = .title
    @Published var searchText = ""
    @Published var isBusy = false
    @Published var isMatchingArtwork = false
    @Published var activityText = ""
    @Published var errorMessage: String?
    @Published var selectedItem: MediaItem?
    @Published var playingItem: MediaItem?
    @Published var showsSettings = false
    @Published var automaticArtwork = true
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly

    init(
        paths: PortablePaths = .init(),
        metadataProvider: any MetadataProvider = CinemetaMetadataProvider()
    ) {
        self.paths = paths
        self.database = LibraryDatabase(paths: paths)
        self.scanner = MediaScanner()
        self.artworkService = ArtworkService(paths: paths)
        self.metadataArtworkService = MetadataArtworkService(paths: paths)
        self.metadataProvider = metadataProvider
    }

    var hasLibrary: Bool { !libraries.isEmpty }

    var movies: [MediaItem] {
        sorted(media.filter { $0.kind == .movie })
    }

    var series: [TVSeries] {
        Dictionary(grouping: media.filter { $0.kind == .episode }) {
            $0.displayTitle.normalizedForGrouping
        }
        .values
        .compactMap { episodes in
            guard let title = episodes.first?.displayTitle else { return nil }
            return TVSeries(title: title, episodes: episodes)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var continueWatching: [MediaItem] {
        let movies = media.filter { $0.kind == .movie && $0.continueWatching }
        let shows = series.compactMap(\.continueWatchingEpisode)
        return (movies + shows).sorted {
            ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast)
        }
    }

    var recentlyAdded: [MediaItem] {
        let seriesCards = series.compactMap {
            $0.episodes.max { $0.dateAdded < $1.dateAdded }
        }
        return Array(
            (media.filter { $0.kind == .movie } + seriesCards)
                .sorted { $0.dateAdded > $1.dateAdded }
                .prefix(20)
        )
    }

    var genreShelves: [GenreShelf] {
        var grouped: [String: (name: String, items: [MediaItem])] = [:]
        let cards = media.filter { $0.kind == .movie } + series.compactMap(\.representative)
        for item in cards {
            let genres = (item.genre ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for genre in genres {
                let key = genre.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).lowercased()
                var entry = grouped[key] ?? (genre, [])
                if !entry.items.contains(where: { $0.id == item.id }) {
                    entry.items.append(item)
                }
                grouped[key] = entry
            }
        }
        return grouped.values
            .map { GenreShelf(name: $0.name, items: sorted($0.items)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var filteredCards: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        func matchesQuery(_ item: MediaItem) -> Bool {
            query.isEmpty ||
            item.displayTitle.localizedCaseInsensitiveContains(query) ||
            (item.episodeTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
            (item.genre?.localizedCaseInsensitiveContains(query) ?? false) ||
            item.year.map(String.init)?.contains(query) == true
        }

        let movieCards = media.filter { item in
            guard item.kind == .movie, matchesQuery(item) else { return false }
            switch selectedFilter {
            case .all, .movies:
                return true
            case .tvShows:
                return false
            case .watched:
                return item.isWatched
            case .unwatched:
                return !item.isWatched
            case .favorites:
                return item.isFavorite
            }
        }

        let seriesCards = series.compactMap { show -> MediaItem? in
            guard selectedFilter != .movies,
                  let representative = show.representative,
                  show.episodes.contains(where: matchesQuery)
            else { return nil }
            switch selectedFilter {
            case .all, .tvShows:
                return representative
            case .movies:
                return nil
            case .watched:
                return show.episodes.contains(where: \.isWatched) ? representative : nil
            case .unwatched:
                return show.episodes.contains(where: { !$0.isWatched }) ? representative : nil
            case .favorites:
                return show.episodes.contains(where: \.isFavorite) ? representative : nil
            }
        }

        return sorted(movieCards + seriesCards)
    }

    func bootstrap() async {
        do {
            try await database.initialize()
            automaticArtwork = try await database.setting("automatic_artwork") != "false"
            try paths.prepare()
            let matcherVersion = try await database.setting("artwork_matcher_version")
            let matcherNeedsRetry = matcherVersion != "strict-v4"
            if !["strict-v2", "strict-v3", "strict-v4"].contains(matcherVersion) {
                let stalePaths = try await database.resetProviderEnrichment(
                    artworkRoot: paths.artwork.path
                )
                for path in stalePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            try await database.setSetting("artwork_matcher_version", value: "strict-v4")
            try await reload()
            let parserVersion = try await database.setting("filename_parser_version")
            if parserVersion != "season-v2" {
                await repairMediaClassifications()
                try await database.setSetting("filename_parser_version", value: "season-v2")
                try await reload()
            }
            if automaticArtwork &&
                (matcherNeedsRetry || parserVersion != "season-v2") {
                startArtworkEnrichment()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseAndAddLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choose a media folder"
        panel.prompt = "Add Library"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        Task {
            for url in panel.urls {
                await addLibrary(url)
            }
        }
    }

    func addLibrary(_ url: URL) async {
        isBusy = true
        activityText = "Adding \(url.lastPathComponent)…"
        defer {
            isBusy = false
            activityText = ""
        }
        do {
            let bookmark = try? BookmarkAccess.create(for: url)
            let library = LibraryFolder(
                displayName: url.lastPathComponent,
                path: url.path,
                bookmark: bookmark
            )
            try await database.addLibrary(library)
            try await reload()
            await scan(library)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        for library in libraries where library.isEnabled {
            await scan(library)
        }
    }

    func scan(_ library: LibraryFolder) async {
        isBusy = true
        activityText = "Scanning \(library.displayName)…"
        let report = await scanner.scan(library: library)
        do {
            try await database.ingest(report, for: library.id)
            try await reload()
            if let firstError = report.errors.first {
                errorMessage = "Scan finished with \(report.errors.count) warning(s). \(firstError)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
        activityText = ""
        if automaticArtwork {
            startArtworkEnrichment()
        }
    }

    func setAutomaticArtwork(_ enabled: Bool) async {
        automaticArtwork = enabled
        try? await database.setSetting("automatic_artwork", value: enabled ? "true" : "false")
        if enabled {
            startArtworkEnrichment()
        }
    }

    func toggleFavorite(_ item: MediaItem) async {
        do {
            try await database.setFavorite(mediaID: item.id, favorite: !item.isFavorite)
            try await reload()
            selectedItem = media.first { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restart(_ item: MediaItem) async {
        do {
            try await database.restart(mediaID: item.id)
            try await reload()
            playingItem = media.first { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markFinished(_ item: MediaItem, duration: Double? = nil) async {
        do {
            try await database.markFinished(
                mediaID: item.id,
                duration: duration ?? item.runtime
            )
            try await reload()
            if selectedItem?.id == item.id {
                selectedItem = media.first { $0.id == item.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProgress(_ item: MediaItem, position: Double, duration: Double?) async {
        do {
            let threshold = Double(try await database.setting("watched_threshold") ?? "0.90") ?? 0.90
            try await database.updateProgress(
                mediaID: item.id,
                position: position,
                duration: duration,
                watchedThreshold: threshold
            )
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMetadata(
        _ item: MediaItem,
        title: String,
        year: Int?,
        summary: String?,
        genre: String?,
        runtime: Double?,
        episodeTitle: String?
    ) async {
        do {
            try await database.updateMetadata(
                mediaID: item.id,
                title: title,
                year: year,
                summary: summary,
                genre: genre,
                runtime: runtime,
                episodeTitle: episodeTitle
            )
            try await reload()
            selectedItem = media.first { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseArtwork(for item: MediaItem, role: ArtworkRole) {
        let panel = NSOpenPanel()
        panel.title = role == .poster ? "Choose Poster" : "Choose Backdrop"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importArtwork(from: url, for: item, role: role)
    }

    func importArtwork(from url: URL, for item: MediaItem, role: ArtworkRole) {
        Task {
            do {
                let destination = try await artworkService.importArtwork(
                    from: url,
                    for: item.id,
                    kind: item.kind,
                    role: role
                )
                try await database.setArtwork(
                    mediaID: item.id,
                    role: role,
                    path: destination.path,
                    manual: true
                )
                try await reload()
                selectedItem = media.first { $0.id == item.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeArtwork(from item: MediaItem, role: ArtworkRole) async {
        do {
            try await artworkService.removeArtwork(for: item.id, kind: item.kind, role: role)
            try await database.setArtwork(mediaID: item.id, role: role, path: nil, manual: false)
            try await reload()
            selectedItem = media.first { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeLibrary(_ library: LibraryFolder) async {
        do {
            try await database.removeLibrary(id: library.id)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLibraryEnabled(_ library: LibraryFolder, enabled: Bool) async {
        do {
            try await database.setLibraryEnabled(id: library.id, enabled: enabled)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPortableDataInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    func showMediaInFinder(_ item: MediaItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.mediaURL])
    }

    func reload() async throws {
        libraries = try await database.libraries()
        media = try await database.allMedia()
    }

    func toggleSidebar() {
        sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
    }

    func nextEpisode(after item: MediaItem) -> MediaItem? {
        guard item.kind == .episode, item.episodeNumber != nil else { return nil }
        let episodes = media
            .filter {
                $0.kind == .episode &&
                $0.episodeNumber != nil &&
                $0.displayTitle.caseInsensitiveCompare(item.displayTitle) == .orderedSame
            }
            .sorted {
                ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) <
                ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
            }
        guard let index = episodes.firstIndex(where: { $0.id == item.id }),
              episodes.indices.contains(index + 1)
        else { return nil }
        return episodes[index + 1]
    }

    func playNextEpisode(after item: MediaItem) {
        guard let next = nextEpisode(after: item) else {
            playingItem = nil
            return
        }
        playingItem = next
    }

    private func sorted(_ input: [MediaItem]) -> [MediaItem] {
        switch selectedSort {
        case .title:
            return input.sorted {
                ($0.sortTitle ?? $0.displayTitle)
                    .localizedStandardCompare($1.sortTitle ?? $1.displayTitle) == .orderedAscending
            }
        case .recentlyAdded:
            return input.sorted { $0.dateAdded > $1.dateAdded }
        case .recentlyWatched:
            return input.sorted {
                ($0.lastWatched ?? .distantPast) > ($1.lastWatched ?? .distantPast)
            }
        case .year:
            return input.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    private func repairMediaClassifications() async {
        let parser = FilenameParser()
        for item in media {
            let parsed = parser.parse(url: item.mediaURL)
            let changed = parsed.kind != item.kind ||
                parsed.title != item.parsedTitle ||
                parsed.seasonNumber != item.seasonNumber ||
                parsed.episodeNumber != item.episodeNumber
            guard changed else { continue }
            do {
                try await database.reclassify(mediaID: item.id, parsed: parsed)
                if parsed.kind != item.kind {
                    if let poster = item.posterPath,
                       !item.manualPoster,
                       poster.hasPrefix(paths.artwork.path) {
                        try? FileManager.default.removeItem(atPath: poster)
                        try await database.setArtwork(
                            mediaID: item.id,
                            role: .poster,
                            path: nil,
                            manual: false
                        )
                    }
                    if let backdrop = item.backdropPath,
                       !item.manualBackdrop,
                       backdrop.hasPrefix(paths.artwork.path) {
                        try? FileManager.default.removeItem(atPath: backdrop)
                        try await database.setArtwork(
                            mediaID: item.id,
                            role: .backdrop,
                            path: nil,
                            manual: false
                        )
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func enrichMissingArtwork() async {
        let movieTargets = media.filter {
            $0.kind == .movie && !$0.manualPoster && $0.posterPath == nil
        }
        for item in movieTargets {
            await enrich(group: [item], queryTitle: item.displayTitle, year: item.year, kind: .movie)
        }

        let episodeGroups = Dictionary(grouping: media.filter {
            $0.kind == .episode && !$0.manualPoster && $0.posterPath == nil
        }) { $0.displayTitle.normalizedForGrouping }
        for episodes in episodeGroups.values {
            guard let first = episodes.first else { continue }
            await enrich(
                group: episodes,
                queryTitle: first.displayTitle,
                year: first.year,
                kind: .episode
            )
        }
    }

    private func startArtworkEnrichment() {
        guard !isMatchingArtwork else { return }
        isMatchingArtwork = true
        Task {
            await enrichMissingArtwork()
            try? await reload()
            isMatchingArtwork = false
        }
    }

    private func enrich(
        group: [MediaItem],
        queryTitle: String,
        year: Int?,
        kind: MediaKind
    ) async {
        do {
            guard let match = try await metadataProvider.bestMatch(
                title: queryTitle,
                year: year,
                kind: kind
            ), let representative = group.first else { return }

            var posterPath: String?
            var backdropPath: String?
            if let posterURL = match.posterURL {
                posterPath = try? await metadataArtworkService.download(
                    from: posterURL,
                    mediaID: representative.id,
                    kind: kind,
                    role: .poster
                ).path
            }
            if let backdropURL = match.backdropURL {
                backdropPath = try? await metadataArtworkService.download(
                    from: backdropURL,
                    mediaID: representative.id,
                    kind: kind,
                    role: .backdrop
                ).path
            }

            for item in group {
                try await database.applyProviderMetadata(
                    mediaID: item.id,
                    summary: match.summary,
                    genre: match.genres.joined(separator: ", ").nonEmpty,
                    year: match.year
                )
                if let posterPath, !item.manualPoster {
                    try await database.setArtwork(
                        mediaID: item.id,
                        role: .poster,
                        path: posterPath,
                        manual: false
                    )
                }
                if let backdropPath, !item.manualBackdrop {
                    try await database.setArtwork(
                        mediaID: item.id,
                        role: .backdrop,
                        path: backdropPath,
                        manual: false
                    )
                }
            }
        } catch {
            // Online artwork is best-effort. Offline use remains silent and fully functional.
        }
    }
}

private extension String {
    var normalizedForGrouping: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
