import Foundation

struct UpdateOffer: Sendable, Equatable {
    let latestVersion: String
    let currentVersion: String
    let downloadURL: URL
    let sha256URL: URL?
    let releaseNotes: String?
}

protocol UpdateChecking: Sendable {
    func checkForUpdate() async -> UpdateOffer?
}

struct UpdateCheckService: UpdateChecking {
    private let config: AppConfig
    private let session: URLSession
    private let currentVersionProvider: @Sendable () -> String
    private let checkInterval: TimeInterval
    private let defaults: UserDefaults

    private static let maxResponseSize = 8 * 1024 * 1024

    init(
        config: AppConfig = .shared,
        session: URLSession = .shared,
        currentVersionProvider: @escaping @Sendable () -> String = { AppVersion.current() },
        checkInterval: TimeInterval = 6 * 60 * 60,
        defaults: UserDefaults = .standard
    ) {
        self.config = config
        self.session = session
        self.currentVersionProvider = currentVersionProvider
        self.checkInterval = checkInterval
        self.defaults = defaults
    }

    /// Check interval in seconds. The API is not called again within 6 hours.
    private static let minimumCheckInterval: TimeInterval = 6 * 60 * 60

    func checkForUpdate() async -> UpdateOffer? {
        guard config.updateCheckEnabled else {
            return nil
        }

        // Skip if within the interval since the last check (prevents an API call on every launch)
        if let lastCheck = defaults.object(forKey: "lastUpdateCheckDate") as? Date,
           Date().timeIntervalSince(lastCheck) < checkInterval {
            return nil
        }

        do {
            let release = try await fetchLatestRelease()
            defaults.set(Date(), forKey: "lastUpdateCheckDate")
            defaults.set(release.etag, forKey: "updateETag")
            let currentVersion = AppVersion.normalize(currentVersionProvider())
            let latestVersion = AppVersion.normalize(release.tagName)

            guard AppVersion.isNewer(latestVersion, than: currentVersion) else {
                AppLogger.info(
                    "App is up to date (current: \(currentVersion), latest: \(latestVersion))",
                    logger: AppLogger.general
                )
                return nil
            }

            guard let downloadURL = resolveDownloadURL(from: release.assets) else {
                AppLogger.error("Update check failed: no allowed download URL", logger: AppLogger.general)
                return nil
            }

            return UpdateOffer(
                latestVersion: latestVersion,
                currentVersion: currentVersion,
                downloadURL: downloadURL,
                sha256URL: resolveSHA256URL(from: release.assets),
                releaseNotes: release.body
            )
        } catch let error as UpdateCheckError {
            if case .notModified = error {
                // 304 Not Modified: no changes. No error log needed.
                return nil
            }
            AppLogger.error("Update check failed: \(error)", logger: AppLogger.general)
            return nil
        } catch {
            AppLogger.error("Update check failed: \(error)", logger: AppLogger.general)
            return nil
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: config.githubReleasesAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Transnote", forHTTPHeaderField: "User-Agent")

        // If there is an ETag from the previous fetch, send it as If-None-Match; a 304 means no update
        if let etag = defaults.string(forKey: "updateETag") {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        // Response size limit (8 MB)
        guard data.count <= Self.maxResponseSize else {
            throw UpdateCheckError.responseTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 304 {
                throw UpdateCheckError.notModified
            }
            throw UpdateCheckError.httpStatus(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard isValidRepository(release) else {
            throw UpdateCheckError.invalidResponse
        }
        return release
    }

    /// If `repository.full_name` is present, it must match the expected value. `html_url` is always validated, whether the field is missing or matches.
    private func isValidRepository(_ release: GitHubRelease) -> Bool {
        if let fullName = release.repository?.fullName,
           fullName != config.expectedGitHubRepository {
            return false
        }
        return UpdateRepositoryValidator.matchesReleaseHTMLURL(
            release.htmlURL,
            expectedRepository: config.expectedGitHubRepository
        )
    }

    private func resolveSHA256URL(from assets: [GitHubReleaseAsset]) -> URL? {
        guard let asset = assets.first(where: { $0.name.hasSuffix(".sha256") }) else {
            return nil
        }
        return UpdateURLValidator.isAllowedDownloadURL(
            asset.browserDownloadURL,
            allowedHosts: config.allowedUpdateDownloadHosts
        ) ? asset.browserDownloadURL : nil
    }

    private func resolveDownloadURL(from assets: [GitHubReleaseAsset]) -> URL? {
        guard let preferred = assets.first(where: { $0.name == config.updateDMGAssetName }) else {
            return validatedFallbackURL()
        }

        return UpdateURLValidator.validatedDownloadURL(
            preferred.browserDownloadURL,
            fallback: config.updateDownloadFallbackURL,
            allowedHosts: config.allowedUpdateDownloadHosts
        )
    }

    private func validatedFallbackURL() -> URL? {
        UpdateURLValidator.isAllowedDownloadURL(
            config.updateDownloadFallbackURL,
            allowedHosts: config.allowedUpdateDownloadHosts
        ) ? config.updateDownloadFallbackURL : nil
    }
}

enum UpdateCheckError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case notModified
    case responseTooLarge
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]
    let htmlURL: URL
    let repository: GitHubReleaseRepository?
    let etag: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
        case htmlURL = "html_url"
        case repository
        case etag
    }
}

private struct GitHubReleaseRepository: Decodable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
