import XCTest
@testable import LocalTranscriber

final class UpdateURLValidatorTests: XCTestCase {
    private let allowedHosts = ["github.com", "objects.githubusercontent.com"]

    // Given: an HTTPS URL that exactly matches an allowed host
    // When: isAllowedDownloadURL is run
    // Then: returns true
    func testIsAllowedDownloadURLAcceptsExactHostMatch() {
        XCTAssertTrue(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertTrue(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: a URL on a subdomain of an allowed host
    // When: isAllowedDownloadURL is run
    // Then: returns false
    func testIsAllowedDownloadURLRejectsSubdomainWildcard() {
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://evil.github.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://cdn.objects.githubusercontent.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: a non-HTTPS URL or a disallowed host
    // When: isAllowedDownloadURL is run
    // Then: returns false
    func testIsAllowedDownloadURLRejectsNonHTTPSAndUnknownHosts() {
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "http://github.com/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://evil.example.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: an html_url returned by the GitHub Releases API
    // When: matchesReleaseHTMLURL is run
    // Then: true for the expected repository
    func testMatchesReleaseHTMLURLAcceptsGitHubReleasePage() {
        XCTAssertTrue(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/tag/v1.0.8")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: a URL on a different host with the expected repository string embedded in the query
    // When: matchesReleaseHTMLURL is run
    // Then: returns false
    func testMatchesReleaseHTMLURLRejectsEmbeddedRepositorySubstring() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://evil.example/redirect?x=github.com/T3pp31/Transnote")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: a release page of a different repository
    // When: matchesReleaseHTMLURL is run
    // Then: returns false
    func testMatchesReleaseHTMLURLRejectsOtherRepository() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/evil/OtherApp/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: a different repository whose name shares a prefix with the expected one
    // When: matchesReleaseHTMLURL is run
    // Then: returns false
    func testMatchesReleaseHTMLURLRejectsRepositoryNamePrefix() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote-malware/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: a host other than github.com, or a non-HTTPS URL
    // When: matchesReleaseHTMLURL is run
    // Then: returns false
    func testMatchesReleaseHTMLURLRejectsNonGitHubHostsAndHTTP() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "http://github.com/T3pp31/Transnote/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com.evil.com/T3pp31/Transnote/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: /releases or /releases/latest without a tag
    // When: matchesReleaseHTMLURL is run
    // Then: returns false
    func testMatchesReleaseHTMLURLRejectsReleasesPathWithoutTag() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/latest")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/anything")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: a release page URL whose tag name contains `/`
    // When: matchesReleaseHTMLURL is run
    // Then: true if owner/repo match
    func testMatchesReleaseHTMLURLAcceptsTagContainingSlash() {
        XCTAssertTrue(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/tag/v1.0/rc1")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
        XCTAssertTrue(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/tag/v1.0%2Frc1")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }
}
