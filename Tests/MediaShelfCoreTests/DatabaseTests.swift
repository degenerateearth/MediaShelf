import Foundation
import XCTest
@testable import MediaShelfCore

final class DatabaseTests: XCTestCase {
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
}
