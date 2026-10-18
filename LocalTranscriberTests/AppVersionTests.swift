import XCTest
@testable import LocalTranscriber

final class AppVersionTests: XCTestCase {
    // Given: identical version strings
    // When: compare is run
    // Then: returns orderedSame
    func testCompareReturnsSameForEqualVersions() {
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("v0.1.0", to: "0.1.0"), .orderedSame)
    }

    // Given: a newer and an older version
    // When: compare is run
    // Then: returns the correct ordering
    func testCompareOrdersSemanticVersions() {
        XCTAssertEqual(AppVersion.compare("0.2.0", to: "0.1.0"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.2.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.10.0", to: "0.9.0"), .orderedDescending)
    }

    // Given: a tag name prefixed with v
    // When: normalize is run
    // Then: the v is removed
    func testNormalizeStripsVersionPrefix() {
        XCTAssertEqual(AppVersion.normalize("v0.2.0"), "0.2.0")
        XCTAssertEqual(AppVersion.normalize("V1.0.0"), "1.0.0")
    }

    // Given: candidate newer versions
    // When: isNewer is run
    // Then: judges as expected
    func testIsNewerDetectsAvailableUpdate() {
        XCTAssertTrue(AppVersion.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertTrue(AppVersion.isNewer("0.1.0", than: "0.1.0-rc1"))
    }

    // Given: a stable and a prerelease version
    // When: compare is run
    // Then: the prerelease version is smaller
    func testCompareOrdersStableVersionsAfterPrereleases() {
        XCTAssertEqual(AppVersion.compare("0.1.0-alpha", to: "0.1.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.1.0-beta", to: "0.1.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-rc1", to: "1.0.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0-rc1"), .orderedDescending)
    }

    // Given: prereleases within the same major line
    // When: compare is run
    // Then: judged lexically and numerically per the SemVer spec
    func testCompareOrdersPrereleases() {
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha", to: "1.0.0-beta"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha.1", to: "1.0.0-alpha.2"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-1", to: "1.0.0-alpha"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha.10", to: "1.0.0-alpha.9"), .orderedDescending)
    }

    // Given: a prerelease tag with a v prefix
    // When: normalized and then compared
    // Then: same result as without the prefix
    func testCompareAfterNormalizingPrefixedPrerelease() {
        XCTAssertEqual(AppVersion.compare("v0.2.0-rc1", to: "0.2.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("v0.1.0-rc1", to: "0.1.0"), .orderedAscending)
    }

    // Given: a version with build metadata
    // When: compare is run
    // Then: build metadata does not affect the comparison
    func testCompareIgnoresBuildMetadata() {
        XCTAssertEqual(AppVersion.compare("0.1.0+build5", to: "0.1.0+build9"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0+build2"), .orderedSame)
    }

    // Given: a version with both prerelease and build metadata
    // When: compare is run
    // Then: compared by prerelease, with build metadata ignored
    func testCompareWithBothPrereleaseAndBuildMetadata() {
        XCTAssertEqual(AppVersion.compare("0.1.0-rc1+build5", to: "0.1.0-rc1+build9"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.1.0-rc1+build5", to: "0.1.0"), .orderedAscending)
    }

    // Given: core numbers that do not fit in Int
    // When: compare is run
    // Then: they do not overflow to 0, and the larger one is newer
    func testCompareDoesNotOverflowLargeCoreNumbers() {
        XCTAssertEqual(
            AppVersion.compare("9223372036854775808.0.0", to: "2.0.0"),
            .orderedDescending
        )
        XCTAssertEqual(
            AppVersion.compare("2.0.0", to: "9223372036854775808.0.0"),
            .orderedAscending
        )
        XCTAssertEqual(
            AppVersion.compare("9223372036854775808.0.0", to: "9223372036854775808.0.0"),
            .orderedSame
        )
    }

    // Given: a prerelease identifier that looks signed
    // When: compare is run
    // Then: only ASCII digits count as numeric identifiers, so "-1" is non-numeric and greater than 0
    func testCompareTreatsSignedPrereleaseIdentifierAsNonNumeric() {
        XCTAssertEqual(AppVersion.compare("1.0.0--1", to: "1.0.0-0"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("1.0.0-0", to: "1.0.0--1"), .orderedAscending)
    }
}
