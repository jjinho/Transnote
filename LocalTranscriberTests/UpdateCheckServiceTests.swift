import XCTest
@testable import LocalTranscriber

final class UpdateCheckServiceTests: XCTestCase {
    private var session: URLSession!
    private var config: AppConfig!

    override func setUp() {
        super.setUp()
        // Clear the check interval and ETag state so they do not carry over between tests
        UserDefaults.standard.removeObject(forKey: "lastUpdateCheckDate")
        UserDefaults.standard.removeObject(forKey: "updateETag")
        MockURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        config = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: true,
            githubReleasesAPIURL: URL(string: "https://api.github.com/repos/T3pp31/Transnote/releases/latest")!,
            updateDownloadFallbackURL: URL(
                string: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg"
            )!,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: ["github.com", "objects.githubusercontent.com"],
            maxImportFileSizeBytes: 524_288_000
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        config = nil
        super.tearDown()
    }

    // Given: a release newer than the current version, with a DMG asset
    // When: checkForUpdate is run
    // Then: returns an UpdateOffer
    func testCheckForUpdateReturnsOfferWhenNewerVersionExists() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()

        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(offer?.currentVersion, "0.1.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
        XCTAssertEqual(offer?.releaseNotes, "Bug fixes")
    }

    // Given: a release equal to the current version
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenUpToDate() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.1.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.1.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": []
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: a release without assets
    // When: checkForUpdate is run
    // Then: uses the fallback URL
    func testCheckForUpdateUsesFallbackWhenAssetMissing() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": []
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
    }

    // Given: an invalid download URL is returned
    // When: checkForUpdate is run
    // Then: uses the fallback URL
    func testCheckForUpdateUsesFallbackWhenAssetURLIsNotAllowed() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://evil.example.com/malware.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
    }

    // Given: an invalid asset URL and an invalid fallback
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenNoAllowedDownloadURL() async {
        let unsafeConfig = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: true,
            githubReleasesAPIURL: config.githubReleasesAPIURL,
            updateDownloadFallbackURL: URL(string: "https://evil.example.com/fallback.dmg")!,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: ["github.com", "objects.githubusercontent.com"],
            maxImportFileSizeBytes: 524_288_000
        )

        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "file:///tmp/malware.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: unsafeConfig.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: unsafeConfig,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: a release with only .dmg files other than the expected DMG attached
    // When: checkForUpdate is run
    // Then: uses the fallback URL
    func testCheckForUpdateUsesFallbackWhenOnlyUnexpectedDMGExists() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Other.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Other.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
    }

    // Given: a release response from a different repository
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenRepositoryDoesNotMatch() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/evil/OtherApp/releases/tag/v0.2.0",
              "repository": {
                "full_name": "evil/OtherApp"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: a different repository whose html_url embeds the expected repository string
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenRepositoryHTMLURLContainsExpectedPath() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/redirect?x=github.com/T3pp31/Transnote",
              "repository": {
                "full_name": "evil/OtherApp"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: a new release shaped like the GitHub REST API response (no repository field)
    // When: checkForUpdate is run
    // Then: validates the repository from html_url and returns an UpdateOffer
    func testCheckForUpdateReturnsOfferWhenRepositoryFieldIsAbsent() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()

        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(offer?.currentVersion, "0.1.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
    }

    // Given: no repository field, with the expected repository string only embedded in html_url
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenRepositoryFieldIsAbsentAndHTMLURLIsUnrelated() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/redirect?x=github.com/T3pp31/Transnote",
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository.full_name does not match; html_url is the expected repository
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenRepositoryFullNameConflictsWithHTMLURL() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "evil/OtherApp"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository.full_name is the expected repository; html_url is a different host
    // When: checkForUpdate is run
    // Then: rejected by html_url validation; returns nil
    func testCheckForUpdateReturnsNilWhenRepositoryFullNameMatchesButHTMLURLDoesNot() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/malicious-release",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository is JSON null; html_url is the expected repository
    // When: checkForUpdate is run
    // Then: returns an UpdateOffer
    func testCheckForUpdateReturnsOfferWhenRepositoryFieldIsNull() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": null,
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
    }

    // Given: html_url is /releases without a tag
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilWhenHTMLURLLacksReleaseTag() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases",
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: the API returns an error
    // When: checkForUpdate is run
    // Then: returns nil
    func testCheckForUpdateReturnsNilOnHTTPError() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: update checks are disabled
    // When: checkForUpdate is run
    // Then: returns nil without touching the network
    func testCheckForUpdateSkipsWhenDisabled() async {
        let disabledConfig = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: false,
            githubReleasesAPIURL: config.githubReleasesAPIURL,
            updateDownloadFallbackURL: config.updateDownloadFallbackURL,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: config.allowedUpdateDownloadHosts,
            maxImportFileSizeBytes: config.maxImportFileSizeBytes
        )

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Network should not be called when update check is disabled")
            fatalError("unreachable")
        }

        let service = UpdateCheckService(
            config: disabledConfig,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
