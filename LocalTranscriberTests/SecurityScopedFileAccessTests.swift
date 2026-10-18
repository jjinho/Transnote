import XCTest
@testable import LocalTranscriber

final class SecurityScopedFileAccessTests: XCTestCase {
    private var access: SecurityScopedFileAccess!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        access = SecurityScopedFileAccess()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testBeginAccessThrowsForMissingFile() {
        let missing = tempRoot.appendingPathComponent("missing.wav")
        XCTAssertThrowsError(try access.beginAccess(url: missing)) { error in
            guard case AppError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }

    func testLastExportDirectoryBookmarkRoundTrip() throws {
        let directory = tempRoot.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "lastExportDirectoryBookmark")
        defer { UserDefaults.standard.removeObject(forKey: "lastExportDirectoryBookmark") }

        access.saveLastExportDirectoryBookmark(for: directory)

        XCTAssertEqual(
            access.loadLastExportDirectory()?.standardizedFileURL,
            directory.standardizedFileURL
        )
    }

    func testEndAccessIsNoOpForUnknownURL() {
        // endAccess on a URL that was never started does not crash and does nothing
        let url = tempRoot.appendingPathComponent("not-started.wav")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        access.endAccess(url: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testEndAllAccessIsSafeWhenNothingStarted() {
        access.endAllAccess()
        // Does not throw even if nothing was started
        XCTAssertTrue(true)
    }

    func testResolveBookmarkThrowsForInvalidData() {
        XCTAssertThrowsError(try access.resolveBookmark(Data()))
    }
}
