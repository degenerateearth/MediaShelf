import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case movie
    case episode
}

public enum LibraryAvailability: String, Codable, Sendable {
    case available
    case unavailable
    case possiblyRemoved
}

public enum ArtworkRole: String, Codable, Sendable {
    case poster
    case backdrop
    case thumbnail
}

public struct LibraryFolder: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var path: String
    public var bookmark: Data?
    public var isEnabled: Bool
    public var dateAdded: Date
    public var lastScanned: Date?
    public var availability: LibraryAvailability

    public init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        bookmark: Data? = nil,
        isEnabled: Bool = true,
        dateAdded: Date = .now,
        lastScanned: Date? = nil,
        availability: LibraryAvailability = .available
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmark = bookmark
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
        self.lastScanned = lastScanned
        self.availability = availability
    }
}

public struct ParsedFilename: Equatable, Sendable {
    public var kind: MediaKind
    public var title: String
    public var year: Int?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var episodeTitle: String?

    public init(
        kind: MediaKind,
        title: String,
        year: Int? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.year = year
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
    }
}

public struct ScanCandidate: Sendable {
    public var stableID: String
    public var libraryID: UUID
    public var absolutePath: String
    public var relativePath: String
    public var filename: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var parsed: ParsedFilename
    public var localPosterPath: String?
    public var localBackdropPath: String?

    public init(
        stableID: String,
        libraryID: UUID,
        absolutePath: String,
        relativePath: String,
        filename: String,
        fileSize: Int64,
        modifiedAt: Date,
        parsed: ParsedFilename,
        localPosterPath: String? = nil,
        localBackdropPath: String? = nil
    ) {
        self.stableID = stableID
        self.libraryID = libraryID
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.filename = filename
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.parsed = parsed
        self.localPosterPath = localPosterPath
        self.localBackdropPath = localBackdropPath
    }
}

public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var libraryID: UUID
    public var kind: MediaKind
    public var absolutePath: String
    public var relativePath: String
    public var filename: String
    public var fileSize: Int64
    public var modifiedAt: Date
    public var parsedTitle: String
    public var displayTitle: String
    public var sortTitle: String?
    public var year: Int?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var episodeTitle: String?
    public var summary: String?
    public var genre: String?
    public var runtime: Double?
    public var dateAdded: Date
    public var lastWatched: Date?
    public var playbackPosition: Double
    public var isWatched: Bool
    public var isFavorite: Bool
    public var posterPath: String?
    public var backdropPath: String?
    public var thumbnailPath: String?
    public var manualMetadata: Bool
    public var manualPoster: Bool
    public var manualBackdrop: Bool
    public var isAvailable: Bool

    public var effectiveEpisodeTitle: String {
        if let title = episodeTitle?.nonEmpty { return title }
        if let episodeNumber { return "Episode \(episodeNumber)" }
        return "Season \(seasonNumber ?? 0) Video"
    }

    public var episodeCode: String {
        if let episodeNumber {
            return "S\(String(format: "%02d", seasonNumber ?? 0)) E\(String(format: "%02d", episodeNumber))"
        }
        return "Season \(seasonNumber ?? 0)"
    }

    public var progressFraction: Double {
        guard let runtime, runtime > 0 else { return 0 }
        return min(max(playbackPosition / runtime, 0), 1)
    }

    public var continueWatching: Bool {
        playbackPosition > 0 && !isWatched
    }

    public var mediaURL: URL {
        URL(fileURLWithPath: absolutePath)
    }

    public var posterURL: URL? {
        posterPath.map(URL.init(fileURLWithPath:))
    }

    public var backdropURL: URL? {
        backdropPath.map(URL.init(fileURLWithPath:))
    }
}

public struct TVSeries: Identifiable, Hashable, Sendable {
    public var id: String { title.normalizedKey }
    public var title: String
    public var episodes: [MediaItem]

    public init(title: String, episodes: [MediaItem]) {
        self.title = title
        self.episodes = episodes.sorted {
            ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) <
            ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
        }
    }

    public var seasons: [Int] {
        Array(Set(episodes.compactMap(\.seasonNumber))).sorted()
    }

    public var representative: MediaItem? {
        episodes.first
    }
}

public enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case movies = "Movies"
    case tvShows = "TV Shows"
    case watched = "Watched"
    case unwatched = "Unwatched"
    case favorites = "Favorites"

    public var id: String { rawValue }
}

public enum MediaSort: String, CaseIterable, Identifiable, Sendable {
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case recentlyWatched = "Recently Watched"
    case year = "Year"

    public var id: String { rawValue }
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
