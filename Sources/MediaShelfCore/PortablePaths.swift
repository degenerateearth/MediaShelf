import Foundation

public struct PortablePaths: Sendable {
    private static let storedAppDataRootKey = "MediaShelf.appDataRootBookmark"

    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = Self.existingAppDataRoot()
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("MediaShelf Setup", isDirectory: true)
        }
    }

    /// Keeps the database and artwork on the same drive as the selected library.
    public init(libraryURL: URL) {
        self.root = libraryURL
            .deletingLastPathComponent()
            .appendingPathComponent("MediaShelf Files", isDirectory: true)
    }

    public static func existingAppDataRoot(
        bundleURL: URL = Bundle.main.bundleURL,
        defaults: UserDefaults = .standard
    ) -> URL? {
        if let bookmark = defaults.data(forKey: storedAppDataRootKey),
           let resolved = try? BookmarkAccess.resolve(bookmark).url,
           FileManager.default.fileExists(
               atPath: resolved.appendingPathComponent("library.sqlite").path
           ) {
            return resolved
        }

        let appParent = bundleURL.pathExtension == "app"
            ? bundleURL.deletingLastPathComponent()
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = ["MediaShelf Files", "MediaShelf Data"].map {
            appParent.appendingPathComponent($0, isDirectory: true)
        }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("library.sqlite").path)
        }
    }

    public static func rememberAppDataRoot(
        _ root: URL,
        defaults: UserDefaults = .standard
    ) throws {
        defaults.set(try BookmarkAccess.create(for: root), forKey: storedAppDataRootKey)
    }

    public var database: URL { root.appendingPathComponent("library.sqlite") }
    public var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }
    public var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    public var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public var settings: URL { root.appendingPathComponent("Settings", isDirectory: true) }
    public var backups: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public var playback: URL { root.appendingPathComponent("Playback", isDirectory: true) }

    @discardableResult
    public func prepare() throws -> URL {
        let manager = FileManager.default
        for directory in [root, artwork, thumbnails, cache, settings, backups, playback] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return root
    }

    public func artworkDirectory(for mediaID: String, kind: MediaKind) -> URL {
        artwork
            .appendingPathComponent(kind == .movie ? "Movies" : "TV", isDirectory: true)
            .appendingPathComponent(mediaID, isDirectory: true)
    }
}

public enum BookmarkAccess {
    public static func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url, stale)
    }
}
