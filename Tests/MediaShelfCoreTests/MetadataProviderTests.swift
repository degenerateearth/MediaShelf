import Foundation
import XCTest
@testable import MediaShelfCore

final class MetadataProviderTests: XCTestCase {
    private let dexterOriginal = MetadataMatch(
        providerID: "tt0773262",
        title: "Dexter",
        year: 2006,
        summary: nil,
        genres: [],
        posterURL: nil,
        backdropURL: nil
    )
    private let dexterResurrection = MetadataMatch(
        providerID: "tt33043892",
        title: "Dexter: Resurrection",
        year: 2025,
        summary: nil,
        genres: [],
        posterURL: nil,
        backdropURL: nil
    )

    func testRejectsContainmentMatch() {
        let result = CinemetaMetadataProvider.selectExactMatch(
            [dexterResurrection],
            title: "Dexter",
            year: nil
        )
        XCTAssertNil(result)
    }

    func testUsesExactTitle() {
        let result = CinemetaMetadataProvider.selectExactMatch(
            [dexterResurrection, dexterOriginal],
            title: "Dexter",
            year: nil
        )
        XCTAssertEqual(result?.providerID, dexterOriginal.providerID)
    }

    func testRequiresExactYearWhenKnown() {
        let alternate = MetadataMatch(
            providerID: "alternate",
            title: "The Thing",
            year: 1951,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let expected = MetadataMatch(
            providerID: "expected",
            title: "The Thing",
            year: 1982,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let result = CinemetaMetadataProvider.selectExactMatch(
            [alternate, expected],
            title: "The Thing",
            year: 1982
        )
        XCTAssertEqual(result?.providerID, "expected")
    }

    func testRejectsAmbiguousExactTitleWithoutYear() {
        let remake = MetadataMatch(
            providerID: "remake",
            title: "The Thing",
            year: 2011,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let original = MetadataMatch(
            providerID: "original",
            title: "The Thing",
            year: 1982,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let result = CinemetaMetadataProvider.selectExactMatch(
            [remake, original],
            title: "The Thing",
            year: nil
        )
        XCTAssertNil(result)
    }

    func testUsesCanonicalAliasForUpInSmoke() {
        XCTAssertEqual(
            CinemetaMetadataProvider.queryTitles(
                for: "Cheech and Chong Up in Smoke"
            ),
            ["Cheech and Chong Up in Smoke", "Up in Smoke"]
        )
    }

    func testSelectsUniqueUpInSmokeResultFromOriginalSearch() {
        let expected = MetadataMatch(
            providerID: "tt0078446",
            title: "Up in Smoke",
            year: 1978,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let unrelated = MetadataMatch(
            providerID: "tt0087042",
            title: "Cheech & Chong's: The Corsican Brothers",
            year: 1984,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let result = CinemetaMetadataProvider.selectExactMatch(
            [expected, unrelated],
            titles: CinemetaMetadataProvider.queryTitles(
                for: "Cheech and Chong Up in Smoke"
            ),
            year: nil
        )
        XCTAssertEqual(result?.providerID, expected.providerID)
    }

    func testUsesStylizedCanonicalAliasForInglouriousBasterds() {
        XCTAssertEqual(
            CinemetaMetadataProvider.queryTitles(for: "Inglorious Bastards"),
            ["Inglorious Bastards", "Inglourious Basterds"]
        )
    }

    func testCanonicalAliasDoesNotSelectDifferent1978Film() {
        let tarantinoFilm = MetadataMatch(
            providerID: "tt0361748",
            title: "Inglourious Basterds",
            year: 2009,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let originalFilm = MetadataMatch(
            providerID: "tt0076584",
            title: "The Inglorious Bastards",
            year: 1978,
            summary: nil,
            genres: [],
            posterURL: nil,
            backdropURL: nil
        )
        let result = CinemetaMetadataProvider.selectExactMatch(
            [originalFilm, tarantinoFilm],
            title: "Inglourious Basterds",
            year: nil
        )
        XCTAssertEqual(result?.providerID, tarantinoFilm.providerID)
    }
}
