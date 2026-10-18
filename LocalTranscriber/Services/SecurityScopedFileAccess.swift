import Foundation

final class SecurityScopedFileAccess: @unchecked Sendable {
  static let shared = SecurityScopedFileAccess()

  private let lock = NSLock()
  private var activeURLs: [URL] = []

  func beginAccess(url: URL) throws {
    lock.lock()
    defer { lock.unlock() }

    guard FileManager.default.fileExists(atPath: url.path) else {
      throw AppError.fileNotFound
    }

    guard url.startAccessingSecurityScopedResource() else {
      throw AppError.fileAccessDenied
    }

    activeURLs.append(url)
  }

  func endAccess(url: URL) {
    lock.lock()
    defer { lock.unlock() }

    if let index = activeURLs.firstIndex(where: { $0 == url }) {
      url.stopAccessingSecurityScopedResource()
      activeURLs.remove(at: index)
    }
  }

  func endAllAccess() {
    lock.lock()
    defer { lock.unlock() }

    for url in activeURLs {
      url.stopAccessingSecurityScopedResource()
    }
    activeURLs.removeAll()
  }

  func createBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  func resolveBookmark(_ data: Data) throws -> URL {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      AppLogger.info("Bookmark is stale for \(url.lastPathComponent)", logger: AppLogger.fileAccess)
    }

    return url
  }

  // MARK: - Last export directory

  private static let lastExportDirectoryKey = "lastExportDirectoryBookmark"

  /// Saves a security-scoped bookmark for the most recent export directory.
  func saveLastExportDirectoryBookmark(for url: URL) {
    do {
      let data = try createBookmark(for: url)
      UserDefaults.standard.set(data, forKey: Self.lastExportDirectoryKey)
    } catch {
      AppLogger.error(
        "Failed to save last export directory bookmark: \(error)",
        logger: AppLogger.fileAccess
      )
    }
  }

  /// Resolves the saved most recent export directory.
  /// Callers must start security-scoped access with beginAccess(url:) before using it.
  func loadLastExportDirectory() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: Self.lastExportDirectoryKey) else {
      return nil
    }
    do {
      return try resolveBookmark(data)
    } catch {
      AppLogger.error(
        "Failed to resolve last export directory bookmark: \(error)",
        logger: AppLogger.fileAccess
      )
      return nil
    }
  }
}
