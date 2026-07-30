import Foundation

public struct PortablePaths: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let bundleURL = Bundle.main.bundleURL
            if bundleURL.pathExtension == "app" {
                self.root = bundleURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("MediaShelf Data", isDirectory: true)
            } else {
                self.root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("MediaShelf Data", isDirectory: true)
            }
        }
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
