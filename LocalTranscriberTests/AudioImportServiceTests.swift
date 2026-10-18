import XCTest
@testable import LocalTranscriber

final class AudioImportServiceTests: XCTestCase {
    private var importsRoot: URL!
    private var service: AudioImportService!

    override func setUpWithError() throws {
        importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        service = AudioImportService(importsRoot: importsRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: importsRoot)
    }

    func testImportFileCopiesIntoSandboxDirectory() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("sample.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("RIFF".utf8))

        let importedURL = try service.importFile(from: sourceURL)

        XCTAssertTrue(importedURL.path.hasPrefix(importsRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testImportFileSkipsCopyWhenAlreadyInImportsDirectory() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        let importedURL = importsRoot.appendingPathComponent("sample.m4a")
        FileManager.default.createFile(atPath: importedURL.path, contents: Data("test".utf8))

        let result = try service.importFile(from: importedURL)

        XCTAssertEqual(result.standardizedFileURL, importedURL.standardizedFileURL)
    }

    func testImportFileUsesPreferredFileNameWhenSourceNameIsPlaceholder() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        let importedURL = try service.importFile(from: sourceURL, preferredFileName: "recording.m4a")

        XCTAssertEqual(importedURL.pathExtension.lowercased(), "m4a")
        XCTAssertEqual(importedURL.lastPathComponent, "recording.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testImportFileInfersM4AExtensionFromContentTypeForPlaceholderName() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let importedURL = try service.importFile(from: sourceURL)

        XCTAssertEqual(importedURL.pathExtension.lowercased(), "m4a")
        XCTAssertTrue(importedURL.lastPathComponent.hasPrefix("imported-audio"))
    }

    func testImportFileThrowsWhenFileExceedsSizeLimit() throws {
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 10)

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("large.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data(repeating: 0, count: 11))

        XCTAssertThrowsError(try limitedService.importFile(from: sourceURL)) { error in
            guard case AppError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge, got \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importsRoot.appendingPathComponent("large.wav").path))
    }

    func testImportFileSucceedsWhenFileWithinSizeLimit() throws {
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 10)

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("small.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data(repeating: 0, count: 10))

        let importedURL = try limitedService.importFile(from: sourceURL)

        XCTAssertTrue(importedURL.path.hasPrefix(importsRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testValidateAcceptsExtensionFromPreferredFileName() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("PasteboardTemp")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("not-audio".utf8))

        let audioFileService = AudioFileService()
        let info = try audioFileService.validate(url: sourceURL, preferredFileName: "memo.m4a")

        XCTAssertEqual(info.fileExtension, "m4a")
        XCTAssertEqual(info.fileName, "PasteboardTemp")
    }

    // MARK: - partial import file cleanup (#140)

    func testRemoveFileIfExistsIfFailedDeletesZeroByteFile() {
        let zeroByteURL = importsRoot.appendingPathComponent("partial-zero-byte.m4a")
        FileManager.default.createFile(atPath: zeroByteURL.path, contents: nil)

        service.removeFileIfExistsIfFailed(zeroByteURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: zeroByteURL.path))
    }

    func testRemoveFileIfExistsIfFailedIsNoOpForMissingFile() {
        let missingURL = importsRoot.appendingPathComponent("missing.m4a")

        // Does nothing without throwing, even for a nonexistent path
        service.removeFileIfExistsIfFailed(missingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    func testImportFileRemovesPartialFileWhenCopyItemFailsAndStreamingIsSkipped() throws {
        // Simulate copyItem failing "after creating a partial copy"
        let failingManager = PartialCopyThenFailFileManager()
        let serviceWithFailingManager = AudioImportService(
            importsRoot: importsRoot,
            fileManager: failingManager
        )

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("unreadable.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8))
        // Make it unreadable so the fallback to copyFileStreaming also fails
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sourceURL.path)

        let destinationURL = importsRoot.appendingPathComponent("unreadable.wav")

        XCTAssertThrowsError(try serviceWithFailingManager.importFile(from: sourceURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                XCTFail("Expected fileAccessDenied, got \(error)")
                return
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationURL.path),
            "copyItem が部分コピー後に失敗した場合、Imports/ に部分ファイルが残ってはならない"
        )
    }

    func testImportFileFallsBackToStreamingWhenCopyItemFails() throws {
        // Verify that even if copyItem fails, copyFileStreaming copies successfully
        let failingManager = PartialCopyThenFailFileManager()
        let serviceWithFailingManager = AudioImportService(
            importsRoot: importsRoot,
            fileManager: failingManager
        )

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("readable.wav")
        let content = Data("streaming fallback content".utf8)
        FileManager.default.createFile(atPath: sourceURL.path, contents: content)

        let importedURL = try serviceWithFailingManager.importFile(from: sourceURL)

        let importedData = try Data(contentsOf: importedURL)
        XCTAssertEqual(importedData, content)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

// MARK: - cleanup (#187)

    func testCleanupExpiredImportsRemovesOldFilesAndKeepsRecentOnes() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let oldURL = importsRoot.appendingPathComponent("old.m4a")
        let recentURL = importsRoot.appendingPathComponent("recent.m4a")
        FileManager.default.createFile(atPath: oldURL.path, contents: Data("old".utf8))
        FileManager.default.createFile(atPath: recentURL.path, contents: Data("recent".utf8))

        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)

        try service.cleanupExpiredImports(maxAge: 30 * 24 * 60 * 60, now: Date())

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }

    func testCleanupExpiredImportsIsNoOpWhenImportsRootMissing() throws {
        // Does not throw even if importsRoot does not exist
        XCTAssertNoThrow(try service.cleanupExpiredImports())
    }
}

/// A FileManager whose copyItem always fails, leaving a partial file at destination when it does.
/// Test subclass that reproduces a real copyItem failing partway through.
private final class PartialCopyThenFailFileManager: FileManager {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        // Simulate a partial copy: create a 0-byte partial file at destination, then fail
        try? createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        createFile(atPath: dstURL.path, contents: nil)
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSFilePathErrorKey: dstURL.path]
        )
    }
}
