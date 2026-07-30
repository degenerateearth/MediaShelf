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
}
