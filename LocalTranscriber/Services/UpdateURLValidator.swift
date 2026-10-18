import Foundation

enum UpdateURLValidator {
    static func isAllowedDownloadURL(_ url: URL, allowedHosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedHosts.contains { $0.lowercased() == host }
    }

    static func validatedDownloadURL(
        _ candidate: URL,
        fallback: URL,
        allowedHosts: [String]
    ) -> URL? {
        if isAllowedDownloadURL(candidate, allowedHosts: allowedHosts) {
            return candidate
        }
        if isAllowedDownloadURL(fallback, allowedHosts: allowedHosts) {
            return fallback
        }
        return nil
    }
}

enum UpdateRepositoryValidator {
    /// Determines whether the GitHub Releases API `html_url` is a release tag page of the expected repository.
    /// Only `https://github.com/{owner}/{repo}/releases/tag/{tag}` is allowed.
    /// If `{tag}` contains `/`, everything after `releases/tag/` is treated as the tag.
    /// Substring matching, which a repository path embedded in the query could fool, is not used.
    static func matchesReleaseHTMLURL(_ url: URL, expectedRepository: String) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == "github.com" else {
            return false
        }

        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        // A tag name containing `/` may split the path. Everything after owner/repo/releases/tag/ is treated as the tag.
        guard components.count >= 5,
              components[2] == "releases",
              components[3] == "tag" else {
            return false
        }
        let tag = components[4...].joined(separator: "/")
        guard !tag.isEmpty else {
            return false
        }

        return "\(components[0])/\(components[1])" == expectedRepository
    }
}
