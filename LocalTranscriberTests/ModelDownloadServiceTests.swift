import XCTest
@testable import LocalTranscriber

final class ModelDownloadServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var service: ModelDownloadService!
    private var availability: ModelAvailabilityService!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        availability = ModelAvailabilityService(modelsRoot: temporaryRoot)
        service = ModelDownloadService(modelsRoot: temporaryRoot, modelAvailability: availability)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        service = nil
        availability = nil
    }

    func testDownloadIfNeededReturnsExistingPathWithoutNetwork() async throws {
        let variantFolder = temporaryRoot
            .appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        let path = try await service.downloadIfNeeded(
            whisperKitModelName: "base",
            modelDisplayName: "Base"
        )

        XCTAssertEqual(
            path.resolvingSymlinksInPath().path,
            variantFolder.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }

    func testCleanUpFailedDownloadRemovesNewlyCreatedVariantFolderOnly() throws {
        // Given: an existing complete model folder present before the download started (must not be deleted)
        let existingFolder = temporaryRoot
            .appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = existingFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // Given: a snapshot at download start (only the existing model folder)
        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base").map { $0.path }
        )
        XCTAssertEqual(directoriesBeforeDownload.count, 1)
        XCTAssertTrue(
            directoriesBeforeDownload.contains { $0.hasSuffix("models/openai_whisper-base") }
        )

        // Given: a partial folder newly created by a failed download (to be deleted)
        let partialFolder = temporaryRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: partialFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = partialFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When: cleanup after download failure runs
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: only the newly created partial folder is deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialFolder.path))

        // Then: the existing complete model folder is kept
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFolder.path))
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }

    func testCleanUpFailedDownloadRemovesNewlyCreatedHiddenStagingFolder() throws {
        // Given: no hidden staging folder exists before the download starts
        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base", includingHidden: true).map { $0.path }
        )
        XCTAssertTrue(directoriesBeforeDownload.isEmpty)

        // Given: a partial folder left under .cache by a failed WhisperKit download
        let stagingFolder = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = stagingFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: excluded from selection candidates, but removable during cleanup
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingFolder.path))
    }

    func testCleanUpFailedDownloadPreservesHiddenStagingFolderThatExistedBeforeDownload() throws {
        // Given: a hidden staging folder that existed before the download started (must not be deleted)
        let existingStaging = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: existingStaging, withIntermediateDirectories: true)

        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base", includingHidden: true).map { $0.path }
        )
        XCTAssertTrue(directoriesBeforeDownload.contains { $0.hasSuffix("openai_whisper-base") })

        // When: failure cleanup runs
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: the pre-existing hidden folder remains
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingStaging.path))
    }
}
