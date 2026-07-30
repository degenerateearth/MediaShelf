import CryptoKit
import Foundation

public struct ScanReport: Sendable {
    public var candidates: [ScanCandidate]
    public var skippedFiles: Int
    public var errors: [String]

    public init(candidates: [ScanCandidate], skippedFiles: Int, errors: [String]) {
        self.candidates = candidates
        self.skippedFiles = skippedFiles
        self.errors = errors
    }
}

public actor MediaScanner {
    public static let supportedExtensions: Set<String> = ["mp4", "mkv", "m4v", "mov"]

    private let parser: FilenameParser
    private let manager: FileManager

    public init(parser: FilenameParser = .init(), manager: FileManager = .default) {
        self.parser = parser
        self.manager = manager
    }

    public func scan(library: LibraryFolder) -> ScanReport {
        let root = resolvedURL(for: library)
        let gainedAccess = root.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess { root.stopAccessingSecurityScopedResource() }
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .isReadableKey, .isHiddenKey
        ]
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return ScanReport(
                candidates: [],
                skippedFiles: 0,
                errors: ["Could not read \(root.path). The folder may need to be reauthorized."]
            )
        }

        var candidates: [ScanCandidate] = []
        var skipped = 0
        var errors: [String] = []

        for case let url as URL in enumerator {
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true, values.isReadable != false else {
                    skipped += 1
                    continue
                }

                let relativePath = relativePath(for: url, under: root)
                let parsed = parser.parse(url: url)
                let artwork = localArtwork(beside: url)
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? .distantPast

                candidates.append(
                    ScanCandidate(
                        stableID: stableID(
                            libraryID: library.id,
                            relativePath: relativePath,
                            fileSize: size
                        ),
                        libraryID: library.id,
                        absolutePath: url.path,
                        relativePath: relativePath,
                        filename: url.lastPathComponent,
                        fileSize: size,
                        modifiedAt: modified,
                        parsed: parsed,
                        localPosterPath: artwork.poster?.path,
                        localBackdropPath: artwork.backdrop?.path
                    )
                )
            } catch {
                skipped += 1
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return ScanReport(candidates: candidates, skippedFiles: skipped, errors: errors)
    }

    private func resolvedURL(for library: LibraryFolder) -> URL {
        if let bookmark = library.bookmark,
           let resolved = try? BookmarkAccess.resolve(bookmark) {
            return resolved.url
        }
        return URL(fileURLWithPath: library.path)
    }

    private func relativePath(for url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func stableID(libraryID: UUID, relativePath: String, fileSize: Int64) -> String {
        let input = "\(libraryID.uuidString.lowercased())|\(relativePath.lowercased())|\(fileSize)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func localArtwork(beside mediaURL: URL) -> (poster: URL?, backdrop: URL?) {
        let directory = mediaURL.deletingLastPathComponent()
        let posterNames = ["poster.jpg", "poster.jpeg", "poster.png", "folder.jpg", "cover.jpg"]
        let backdropNames = ["backdrop.jpg", "fanart.jpg", "background.jpg"]

        func firstExisting(_ names: [String]) -> URL? {
            for name in names {
                let candidate = directory.appendingPathComponent(name)
                if manager.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }

        return (firstExisting(posterNames), firstExisting(backdropNames))
    }
}
