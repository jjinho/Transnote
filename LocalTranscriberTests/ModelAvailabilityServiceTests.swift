import XCTest
@testable import LocalTranscriber

final class ModelAvailabilityServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var service: ModelAvailabilityService!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        service = ModelAvailabilityService(modelsRoot: temporaryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        service = nil
    }

    func testIsDownloadedReturnsFalseWhenDirectoryMissing() {
        // Given: an empty temporary directory
        // When: checking whether the model exists
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: not downloaded
        XCTAssertFalse(result)
    }

    func testIsDownloadedReturnsFalseWhenVariantPathMissing() {
        // Given: a variant folder without the required files
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try? FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then
        XCTAssertFalse(result)
    }

    func testIsDownloadedReturnsTrueWhenRequiredModelsExist() throws {
        // Given: a variant folder containing the required CoreML files
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(service.modelFolder(for: "base"))
    }

    func testIsDownloadedReturnsFalseWhenRequiredModelFileIsZeroBytes() throws {
        // Given: a variant folder whose required files are 0 bytes (failed mid-download)
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: 0 bytes is treated as incomplete, so not downloaded
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testModelFolderIgnoresParentWhenModelsAreOnlyInChildDirectory() throws {
        // Given: no model in the parent folder; placed only in a child folder
        let parentFolder = temporaryRoot.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let childFolder = parentFolder.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = childFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let folder = service.modelFolder(for: "base")

        // Then: returns the variant folder, not the parent
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-base")
    }

    func testShortVariantNameDoesNotMatchUnrelatedDirectory() throws {
        // Given: required model files placed in an unrelated directory containing "base"
        let decoyFolder = temporaryRoot.appendingPathComponent("models/database", isDirectory: true)
        try FileManager.default.createDirectory(at: decoyFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = decoyFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: "database" contains "base" but is not hyphen-delimited, so it does not match
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testShortVariantNameDoesNotMatchSuffixWithoutHyphen() throws {
        // Given: an unrelated directory ending in "tiny" but not hyphen-delimited
        let decoyFolder = temporaryRoot.appendingPathComponent("models/itiny", isDirectory: true)
        try FileManager.default.createDirectory(at: decoyFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = decoyFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "tiny")

        // Then: "itiny" ends in "tiny" but is not hyphen-delimited, so it does not match
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "tiny"))
    }

    // MARK: - Deterministic selection on tied scores

    /// /var is a symbolic link to /private/var, so URLs returned by the enumerator and
    /// URLs built from temporaryDirectory differ in their real path representation. Both are normalized before comparing.
    private func standardize(_ url: URL?) -> URL? {
        url?.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeVariantFolder(_ name: String, modificationDate: Date?) throws -> URL {
        let folder = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for coreMLName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = folder.appendingPathComponent("\(coreMLName).mlmodelc")
            // 0-byte files are excluded by the "incomplete download" check from #138, so create them with non-zero data
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }
        if let modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: folder.path
            )
        }
        return folder
    }

    func testModelFolderPrefersNewerModificationDateOnEqualScores() throws {
        // Given: two candidate folders with tied scores (suffix match, 80)
        let older = try makeVariantFolder("alpha-base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let newer = try makeVariantFolder("beta-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: the more recently modified one is selected
        XCTAssertEqual(standardize(folder), standardize(newer))
        XCTAssertNotEqual(standardize(folder), standardize(older))
    }

    func testModelFolderPrefersLexicographicallyOrderedNameOnEqualModificationDate() throws {
        // Given: two candidate folders with tied scores and identical modification dates
        let sameDate = Date(timeIntervalSince1970: 1_500_000)
        let alpha = try makeVariantFolder("alpha-base", modificationDate: sameDate)
        let beta = try makeVariantFolder("beta-base", modificationDate: sameDate)

        // When
        let folder = service.modelFolder(for: "base")

        // Then: selected deterministically by name ascending, not enumeration order
        XCTAssertEqual(standardize(folder), standardize(alpha))
        XCTAssertNotEqual(standardize(folder), standardize(beta))
    }

    func testModelFolderPrefersHigherScoreFolder() throws {
        // Given: candidates with a high score (exact match, 100) and a low score (suffix match, 80)
        let exactMatch = try makeVariantFolder("base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let suffixMatch = try makeVariantFolder("custom-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: the high-scoring folder is selected regardless of modification date
        XCTAssertEqual(standardize(folder), standardize(exactMatch))
        XCTAssertNotEqual(standardize(folder), standardize(suffixMatch))
    }

    func testExactVariantMatchBeatsOpenAIWhisperPrefixMatch() throws {
        // Given: candidates with an exact match (100) and an openai_whisper- match (90)
        let exactMatch = try makeVariantFolder("base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let prefixMatch = try makeVariantFolder("openai_whisper-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: the exact match (score 100) wins regardless of modification date
        XCTAssertEqual(standardize(folder), standardize(exactMatch))
        XCTAssertNotEqual(standardize(folder), standardize(prefixMatch))
    }

    func testModelFolderIgnoresHiddenCacheDirectory() throws {
        // Given: a real model folder (older) and a hidden HuggingFace staging folder (newer)
        let realFolder = try makeVariantFolder(
            "openai_whisper-base",
            modificationDate: Date(timeIntervalSince1970: 1_000_000)
        )
        let cacheFolder = try makeVariantFolder(
            ".cache/huggingface/download/openai_whisper-base",
            modificationDate: Date(timeIntervalSince1970: 2_000_000)
        )

        // When
        let folder = service.modelFolder(for: "base")

        // Then: the real folder is selected, not the more recently modified hidden folder
        XCTAssertEqual(standardize(folder), standardize(realFolder))
        XCTAssertNotEqual(standardize(folder), standardize(cacheFolder))
    }

    func testVariantDirectoriesExcludesHiddenByDefaultAndIncludesWhenRequested() throws {
        let visible = try makeVariantFolder("openai_whisper-base", modificationDate: nil)
        let hidden = try makeVariantFolder(
            ".cache/huggingface/download/openai_whisper-base",
            modificationDate: nil
        )

        let visibleOnly = service.variantDirectories(named: "base")
        let withHidden = service.variantDirectories(named: "base", includingHidden: true)

        XCTAssertTrue(visibleOnly.contains { standardize($0) == standardize(visible) })
        XCTAssertFalse(visibleOnly.contains { standardize($0) == standardize(hidden) })
        XCTAssertTrue(withHidden.contains { standardize($0) == standardize(visible) })
        XCTAssertTrue(withHidden.contains { standardize($0) == standardize(hidden) })
    }

    func testModelFolderBreaksIdenticalNameTiesUsingFullPath() throws {
        // Given: two candidates with the same leaf name and modification date, differing only in parent
        let sameDate = Date(timeIntervalSince1970: 1_500_000)
        let repoA = try makeVariantFolder("repo-a/openai_whisper-base", modificationDate: sameDate)
        let repoB = try makeVariantFolder("repo-b/openai_whisper-base", modificationDate: sameDate)

        // When
        let folder = service.modelFolder(for: "base")

        // Then: selected deterministically by normalized path ascending, not enumeration order
        let expectedPath: String? = [repoA, repoB]
            .compactMap { standardize($0)?.path }
            .min()
        XCTAssertEqual(standardize(folder)?.path, expectedPath)
    }

    func testIsDownloadedReturnsFalseWhenRequiredModelBundleDirectoryIsEmpty() throws {
        // Given: a .mlmodelc that is an empty directory (a bundle mid-download)
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundleURL = variantFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: an empty bundle is treated as incomplete
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testIsDownloadedReturnsTrueWhenRequiredModelBundleDirectoryHasContents() throws {
        // Given: a .mlmodelc directory with content (a real CoreML bundle)
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundleURL = variantFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bundleURL.appendingPathComponent("coremldata.bin").path,
                contents: Data("model".utf8)
            )
        }

        // When / Then
        XCTAssertTrue(service.isDownloaded(whisperKitModelName: "base"))
        XCTAssertNotNil(service.modelFolder(for: "base"))
    }
}
