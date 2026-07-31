import Foundation

public struct MetadataMatch: Sendable {
    public var providerID: String
    public var title: String
    public var year: Int?
    public var summary: String?
    public var genres: [String]
    public var posterURL: URL?
    public var backdropURL: URL?

    public init(
        providerID: String,
        title: String,
        year: Int?,
        summary: String?,
        genres: [String],
        posterURL: URL?,
        backdropURL: URL?
    ) {
        self.providerID = providerID
        self.title = title
        self.year = year
        self.summary = summary
        self.genres = genres
        self.posterURL = posterURL
        self.backdropURL = backdropURL
    }
}

public protocol MetadataProvider: Sendable {
    var name: String { get }
    func bestMatch(title: String, year: Int?, kind: MediaKind) async throws -> MetadataMatch?
}

public struct CinemetaMetadataProvider: MetadataProvider {
    public let name = "Cinemeta"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func bestMatch(
        title: String,
        year: Int?,
        kind: MediaKind
    ) async throws -> MetadataMatch? {
        let type = kind == .movie ? "movie" : "series"
        for queryTitle in Self.queryTitles(for: title) {
            guard let encoded = queryTitle.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ), let url = URL(
                string: "https://v3-cinemeta.strem.io/catalog/\(type)/top/search=\(encoded).json"
            ) else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("MediaShelf/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode
            else { continue }

            let payload = try JSONDecoder().decode(CatalogResponse.self, from: data)
            let candidates = payload.metas.map {
                MetadataMatch(
                    providerID: $0.id,
                    title: $0.name,
                    year: Self.extractYear($0.releaseInfo),
                    summary: $0.description,
                    genres: $0.genres ?? [],
                    posterURL: $0.poster.flatMap(URL.init(string:)),
                    backdropURL: $0.background.flatMap(URL.init(string:))
                )
            }
            if let match = Self.selectExactMatch(
                candidates,
                titles: Self.queryTitles(for: title),
                year: year
            ) {
                return match
            }
        }
        return nil
    }

    static func queryTitles(for title: String) -> [String] {
        let aliases = [
            "cheechandchongupinsmoke": "Up in Smoke",
            "ingloriousbastards": "Inglourious Basterds",
        ]
        guard let alias = aliases[title.normalizedForMatching] else {
            return [title]
        }
        return [title, alias]
    }

    static func selectExactMatch(
        _ candidates: [MetadataMatch],
        title: String,
        year: Int?
    ) -> MetadataMatch? {
        let expected = title.normalizedForMatching
        let exactTitles = candidates.filter {
            $0.title.normalizedForMatching == expected
        }
        if let year {
            return exactTitles.first { $0.year == year }
        }
        // Without a year, ambiguity is worse than a placeholder.
        return exactTitles.count == 1 ? exactTitles[0] : nil
    }

    static func selectExactMatch(
        _ candidates: [MetadataMatch],
        titles: [String],
        year: Int?
    ) -> MetadataMatch? {
        for title in titles {
            if let match = selectExactMatch(candidates, title: title, year: year) {
                return match
            }
        }
        return nil
    }

    private static func extractYear(_ value: String?) -> Int? {
        guard let value else { return nil }
        return value
            .split(whereSeparator: { !$0.isNumber })
            .first(where: { $0.count == 4 })
            .flatMap { Int($0) }
    }

    private struct CatalogResponse: Decodable {
        var metas: [CatalogItem]
    }

    private struct CatalogItem: Decodable {
        var id: String
        var name: String
        var poster: String?
        var background: String?
        var description: String?
        var releaseInfo: String?
        var genres: [String]?
    }
}

public actor MetadataArtworkService {
    private let paths: PortablePaths
    private let session: URLSession
    private let manager: FileManager

    public init(
        paths: PortablePaths,
        session: URLSession = .shared,
        manager: FileManager = .default
    ) {
        self.paths = paths
        self.session = session
        self.manager = manager
    }

    public func download(
        from source: URL,
        mediaID: String,
        kind: MediaKind,
        role: ArtworkRole
    ) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: source)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let directory = paths.artworkDirectory(for: mediaID, kind: kind)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let responseExtension = response.suggestedFilename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let ext = responseExtension ?? source.pathExtension.nonEmpty ?? "jpg"
        let destination = directory.appendingPathComponent("\(role.rawValue).\(ext)")
        for candidate in (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? [] where candidate.deletingPathExtension().lastPathComponent == role.rawValue {
            try? manager.removeItem(at: candidate)
        }
        try manager.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}

private extension String {
    var normalizedForMatching: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
