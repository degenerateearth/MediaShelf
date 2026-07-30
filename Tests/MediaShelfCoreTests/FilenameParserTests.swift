import XCTest
@testable import MediaShelfCore

final class FilenameParserTests: XCTestCase {
    private let parser = FilenameParser()

    func testMovieWithParenthesizedYear() {
        let result = parser.parse(filename: "Interstellar (2014)")
        XCTAssertEqual(result.kind, .movie)
        XCTAssertEqual(result.title, "Interstellar")
        XCTAssertEqual(result.year, 2014)
    }

    func testMovieStripsReleaseTags() {
        let result = parser.parse(filename: "Alien.1979.2160p.BluRay.x265")
        XCTAssertEqual(result.title, "Alien")
        XCTAssertEqual(result.year, 1979)
    }

    func testStandardEpisode() {
        let result = parser.parse(filename: "The Expanse - S02E04 - Godspeed")
        XCTAssertEqual(result.kind, .episode)
        XCTAssertEqual(result.title, "The Expanse")
        XCTAssertEqual(result.seasonNumber, 2)
        XCTAssertEqual(result.episodeNumber, 4)
        XCTAssertEqual(result.episodeTitle, "Godspeed")
    }

    func testCompactEpisode() {
        let result = parser.parse(filename: "The.Expanse.S01E01.1080p")
        XCTAssertEqual(result.kind, .episode)
        XCTAssertEqual(result.title, "The Expanse")
        XCTAssertEqual(result.seasonNumber, 1)
        XCTAssertEqual(result.episodeNumber, 1)
        XCTAssertNil(result.episodeTitle)
    }

    func testOneByEpisode() {
        let result = parser.parse(filename: "The.Expanse.1x03")
        XCTAssertEqual(result.kind, .episode)
        XCTAssertEqual(result.title, "The Expanse")
        XCTAssertEqual(result.seasonNumber, 1)
        XCTAssertEqual(result.episodeNumber, 3)
    }

    func testSeasonPackIsTelevisionRatherThanMovie() {
        let result = parser.parse(
            filename: "Ed, Edd N Eddy-1999-S06 1080p RE 10bit EAC3 2 0 x265-iVy"
        )
        XCTAssertEqual(result.kind, .episode)
        XCTAssertEqual(result.title, "Ed, Edd N Eddy")
        XCTAssertEqual(result.year, 1999)
        XCTAssertEqual(result.seasonNumber, 6)
        XCTAssertNil(result.episodeNumber)
    }
}
