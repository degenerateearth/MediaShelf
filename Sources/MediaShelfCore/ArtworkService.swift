import AppKit
import Foundation

public enum ArtworkError: LocalizedError {
    case unsupportedImage

    public var errorDescription: String? {
        "The selected file is not an image that macOS can decode."
    }
}

public actor ArtworkService {
    private let paths: PortablePaths
    private let manager: FileManager

    public init(paths: PortablePaths, manager: FileManager = .default) {
        self.paths = paths
        self.manager = manager
    }

    public func importArtwork(
        from source: URL,
        for mediaID: String,
        kind: MediaKind,
        role: ArtworkRole
    ) throws -> URL {
        guard NSImage(contentsOf: source) != nil else {
            throw ArtworkError.unsupportedImage
        }
        let gainedAccess = source.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess { source.stopAccessingSecurityScopedResource() }
        }

        let directory = paths.artworkDirectory(for: mediaID, kind: kind)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("\(role.rawValue).\(ext)")

        for candidate in (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? [] where candidate.deletingPathExtension().lastPathComponent == role.rawValue {
            try? manager.removeItem(at: candidate)
        }
        try manager.copyItem(at: source, to: destination)
        return destination
    }

    public func removeArtwork(
        for mediaID: String,
        kind: MediaKind,
        role: ArtworkRole
    ) throws {
        let directory = paths.artworkDirectory(for: mediaID, kind: kind)
        for candidate in (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? [] where candidate.deletingPathExtension().lastPathComponent == role.rawValue {
            try manager.removeItem(at: candidate)
        }
    }
}
