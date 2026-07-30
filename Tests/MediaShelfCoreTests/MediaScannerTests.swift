import Foundation
import XCTest
@testable import MediaShelfCore

final class MediaScannerTests: XCTestCase {
    func testRecursiveScanFindsMoviesEpisodesAndLocalArtwork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaShelfScan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let show = root.appendingPathComponent("TV Shows/The Expanse/Season 01")
        let movie = root.appendingPathComponent("Movies/Alien (1979)")
        try FileManager.default.createDirectory(at: show, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movie, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(
            to: show.appendingPathComponent("The Expanse S01E01.mkv")
        )
        try Data("fixture".utf8).write(
            to: movie.appendingPathComponent("Alien.1979.2160p.BluRay.x265.mp4")
        )
        try Data("poster".utf8).write(to: movie.appendingPathComponent("poster.jpg"))

        let library = LibraryFolder(displayName: "Fixture", path: root.path)
        let report = await MediaScanner().scan(library: library)

        XCTAssertEqual(report.candidates.count, 2)
        XCTAssertTrue(report.errors.isEmpty)
        let movieCandidate = try XCTUnwrap(
            report.candidates.first { $0.parsed.kind == .movie }
        )
        XCTAssertEqual(movieCandidate.parsed.title, "Alien")
        XCTAssertNotNil(movieCandidate.localPosterPath)
        let episode = try XCTUnwrap(
            report.candidates.first { $0.parsed.kind == .episode }
        )
        XCTAssertEqual(episode.parsed.seasonNumber, 1)
        XCTAssertEqual(episode.parsed.episodeNumber, 1)
    }
}
