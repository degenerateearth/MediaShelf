import Foundation
import XCTest
@testable import MediaShelfCore

final class DatabaseTests: XCTestCase {
    func testLibraryStorageIsBesideSelectedFolder() {
        let library = URL(fileURLWithPath: "/Volumes/Movies/Library", isDirectory: true)
        let paths = PortablePaths(libraryURL: library)

        XCTAssertEqual(paths.root.path, "/Volumes/Movies/MediaShelf Files")
        XCTAssertEqual(paths.database.path, "/Volumes/Movies/MediaShelf Files/library.sqlite")
    }

    func testIngestPreservesManualMetadataAndProgress() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaShelfTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = PortablePaths(root: root)
        let database = LibraryDatabase(paths: paths)
        try await database.initialize()

        let library = LibraryFolder(displayName: "Movies", path: root.path)
        try await database.addLibrary(library)
        let candidate = ScanCandidate(
            stableID: "stable-id",
            libraryID: library.id,
            absolutePath: "/Volumes/Media/Alien.mkv",
            relativePath: "Alien.mkv",
            filename: "Alien.mkv",
            fileSize: 123,
            modifiedAt: Date(timeIntervalSince1970: 10),
            parsed: ParsedFilename(kind: .movie, title: "Alien", year: 1979)
        )
        try await database.ingest(
            ScanReport(candidates: [candidate], skippedFiles: 0, errors: []),
            for: library.id
        )
        try await database.updateMetadata(
            mediaID: "stable-id",
            title: "ALIEN",
            year: 1979,
            summary: "A manual description",
            genre: "Science Fiction",
            runtime: 7_020
        )
        try await database.updateProgress(
            mediaID: "stable-id",
            position: 1_200,
            duration: 7_020
        )

        try await database.ingest(
            ScanReport(candidates: [candidate], skippedFiles: 0, errors: []),
            for: library.id
        )

        let allMedia = try await database.allMedia()
        let item = try XCTUnwrap(allMedia.first)
        XCTAssertEqual(item.displayTitle, "ALIEN")
        XCTAssertEqual(item.summary, "A manual description")
        XCTAssertEqual(item.playbackPosition, 1_200)
        XCTAssertFalse(item.isWatched)
    }

    func testContinueWatchingUsesFurthestEpisodeAndDoesNotFallBackAfterFinishing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaShelfTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = PortablePaths(root: root)
        let database = LibraryDatabase(paths: paths)
        try await database.initialize()

        let library = LibraryFolder(displayName: "TV", path: root.path)
        try await database.addLibrary(library)
        let episode1 = ScanCandidate(
            stableID: "dexter-s01e01",
            libraryID: library.id,
            absolutePath: "/Volumes/Media/Dexter.S01E01.mkv",
            relativePath: "Dexter/Dexter.S01E01.mkv",
            filename: "Dexter.S01E01.mkv",
            fileSize: 123,
            modifiedAt: Date(timeIntervalSince1970: 10),
            parsed: ParsedFilename(
                kind: .episode,
                title: "Dexter",
                seasonNumber: 1,
                episodeNumber: 1
            )
        )
        let episode11 = ScanCandidate(
            stableID: "dexter-s01e11",
            libraryID: library.id,
            absolutePath: "/Volumes/Media/Dexter.S01E11.mkv",
            relativePath: "Dexter/Dexter.S01E11.mkv",
            filename: "Dexter.S01E11.mkv",
            fileSize: 456,
            modifiedAt: Date(timeIntervalSince1970: 11),
            parsed: ParsedFilename(
                kind: .episode,
                title: "Dexter",
                seasonNumber: 1,
                episodeNumber: 11
            )
        )
        try await database.ingest(
            ScanReport(candidates: [episode1, episode11], skippedFiles: 0, errors: []),
            for: library.id
        )
        try await database.updateProgress(
            mediaID: episode1.stableID,
            position: 300,
            duration: 1_200
        )
        try await database.updateProgress(
            mediaID: episode11.stableID,
            position: 100,
            duration: 1_200
        )

        var items = try await database.allMedia()
        var series = TVSeries(title: "Dexter", episodes: items)
        XCTAssertEqual(series.continueWatchingEpisode?.id, episode11.stableID)

        try await database.markFinished(mediaID: episode11.stableID, duration: 1_200)

        items = try await database.allMedia()
        series = TVSeries(title: "Dexter", episodes: items)
        XCTAssertNil(series.continueWatchingEpisode)
        let finished = try XCTUnwrap(items.first { $0.id == episode11.stableID })
        XCTAssertTrue(finished.isWatched)
        XCTAssertEqual(finished.playbackPosition, 1_200)
    }
}
