import Foundation
import WhisperKit

struct ModelDownloadService: Sendable {
    private let modelsRoot: URL
    private let modelAvailability: ModelAvailabilityService
    private let fileManager: FileManager

    init(
        modelsRoot: URL = AppDirectories.modelsDirectory,
        modelAvailability: ModelAvailabilityService? = nil,
        fileManager: FileManager = .default
    ) {
        self.modelsRoot = modelsRoot
        self.modelAvailability = modelAvailability ?? ModelAvailabilityService(modelsRoot: modelsRoot)
        self.fileManager = fileManager
    }

    /// Returns the model's path if it exists in the given directory; otherwise downloads it.
    func downloadIfNeeded(
        whisperKitModelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)? = nil
    ) async throws -> URL {
        if let existingPath = modelAvailability.modelFolder(for: whisperKitModelName) {
            AppLogger.info(
                "Model already available at \(existingPath.lastPathComponent)",
                logger: AppLogger.transcription
            )
            return existingPath
        }

        return try await download(
            whisperKitModelName: whisperKitModelName,
            modelDisplayName: modelDisplayName,
            progressHandler: progressHandler
        )
    }

    /// Checks whether the free space needed for a model download (5 GB) is available.
    /// When insufficient, reports a dedicated error rather than AppError.fileTooLarge.
    private func ensureEnoughDiskSpace() throws {
        let resourceValues = try? modelsRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = resourceValues?.volumeAvailableCapacityForImportantUsage,
              available > 0 else {
            // Skip the check if the capacity cannot be obtained (non-blocking)
            AppLogger.info("Could not determine free disk space; skipping check", logger: AppLogger.transcription)
            return
        }
        let minimumRequired: Int64 = 5 * 1024 * 1024 * 1024
        if available < minimumRequired {
            AppLogger.error("Insufficient disk space: \(available) bytes available", logger: AppLogger.transcription)
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "モデルのダウンロードに必要な空き容量が不足しています。ディスクの空き容量を確認してください。",
                    comment: "Insufficient disk space for model download"
                )
            )
        }
    }

    /// Deletes the downloaded folder of the given model.
    /// Does nothing if the model has not been downloaded.
    func deleteModel(whisperKitModelName: String) throws {
        guard let folder = modelAvailability.modelFolder(for: whisperKitModelName) else {
            return
        }
        AppLogger.info("Deleting model folder: \(folder.lastPathComponent)", logger: AppLogger.transcription)
        try fileManager.removeItem(at: folder)
    }

    private func download(
        whisperKitModelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> URL {
        AppDirectories.ensureDirectoriesExist()

        // Check free space before downloading (abort if under 5 GB, a rough minimum model size).
        try ensureEnoughDiskSpace()

        AppLogger.info("Downloading model: \(whisperKitModelName)", logger: AppLogger.transcription)
        progressHandler?(
            .make(phase: .downloadingModel, fraction: 0, modelDisplayName: modelDisplayName)
        )

        // If WhisperKit.download throws, partially created folders remain in the destination (modelsRoot).
        // Record the "folders that existed before the download", and on failure delete only the "folders newly created
        // by this download" (a safeguard against accidentally deleting existing models).
        let directoriesBeforeDownload = Set(
            modelAvailability.variantDirectories(
                named: whisperKitModelName,
                includingHidden: true
            ).map { $0.path }
        )

        // Retry with exponential backoff on network failures (up to 3 times, waiting 1s / 2s / 4s).
        let maxAttempts = 3
        var attempt = 0
        var lastError: Error?
        var downloadedPath: URL?
        while attempt < maxAttempts {
            attempt += 1
            do {
                downloadedPath = try await WhisperKit.download(
                    variant: whisperKitModelName,
                    downloadBase: modelsRoot,
                    progressCallback: { progress in
                        // Resume state: if part of the download already exists, show "Resuming from cache"
                        let resumeState = (progress.completedUnitCount ?? 0) > 0
                            ? NSLocalizedString("キャッシュから再開中", comment: "Resuming download")
                            : nil
                        progressHandler?(
                            .make(
                                phase: .downloadingModel,
                                fraction: progress.fractionCompleted,
                                progress: progress,
                                modelDisplayName: modelDisplayName,
                                resumeState: resumeState
                            )
                        )
                    }
                )
                break
            } catch {
                lastError = error
                // Retry only network errors
                guard isRetryableNetworkError(error), attempt < maxAttempts else {
                    throw error
                }
                let delaySeconds = UInt64(pow(2.0, Double(attempt - 1)))
                AppLogger.info("Download attempt \(attempt) failed; retrying in \(delaySeconds)s: \(error)", logger: AppLogger.transcription)
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }

        guard let path = downloadedPath else {
            throw lastError ?? AppError.transcriptionFailed(
                NSLocalizedString("モデルのダウンロードに失敗しました。", comment: "Model download failed")
            )
        }
        guard modelAvailability.validateModelFolder(path) else {
            throw AppError.transcriptionFailed(
                String(
                    format: NSLocalizedString(
                        "モデルのダウンロードは完了しましたが、ファイル構成が不正です: %@",
                        comment: "Downloaded model has invalid file structure"
                    ),
                    path.path
                )
            )
        }

        AppLogger.info("Downloaded model to \(path.lastPathComponent)", logger: AppLogger.transcription)
        return path
    }

    /// Determines whether an error is a network error that should be retried.
    private func isRetryableNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .resourceUnavailable,
                 .cannotFindHost:
                return true
            default:
                return false
            }
        }
        // Of the generic errors WhisperKit throws, retry only those with network-related wording
        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("network")
            || description.contains("connection")
            || description.contains("timeout")
    }

    /// On download failure, deletes the variant folders (partial downloads) newly created by that download.
    /// Only folders that "did not exist beforehand" are deleted; existing models are unaffected.
    /// Extracted as an internal method for testability.
    func cleanUpFailedDownload(
        whisperKitModelName: String,
        directoriesBeforeDownload: Set<String>
    ) {
        for url in modelAvailability.variantDirectories(
            named: whisperKitModelName,
            includingHidden: true
        ) {
            guard !directoriesBeforeDownload.contains(url.path) else { continue }
            AppLogger.info(
                "Removing incomplete model folder after failed download: \(url.lastPathComponent)",
                logger: AppLogger.transcription
            )
            try? fileManager.removeItem(at: url)
        }
    }
}
