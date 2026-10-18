import AVFoundation
import Foundation
import WhisperKit

actor WhisperKitTranscriber: Transcriber {
    private var activeTasks: [UUID: Task<Transcript, Error>] = [:]
    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private let modelAvailability: ModelAvailabilityService

    init(modelAvailability: ModelAvailabilityService = ModelAvailabilityService()) {
        self.modelAvailability = modelAvailability
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)? = nil
    ) async throws -> Transcript {
        // Parallel transcribe calls on the same WhisperKit instance are not allowed.
        // Reject new jobs if activeTasks is non-empty.
        let alreadyActive = !activeTasks.isEmpty
        guard !alreadyActive else {
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "別の文字起こしが実行中のため開始できません。終了を待ってからもう一度お試しください。",
                    comment: "Parallel transcription rejected"
                )
            )
        }

        let task = Task<Transcript, Error> {
            try await self.performTranscription(job: job, progressHandler: progressHandler)
        }

        activeTasks[job.id] = task

        defer {
            activeTasks.removeValue(forKey: job.id)
        }

        return try await task.value
    }

    func cancel(jobID: UUID) async {
        activeTasks[jobID]?.cancel()
    }

    private func performTranscription(
        job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        do {
            try Task.checkCancellation()

            // RTF (Real-Time Factor) measurement: processing time / audio duration.
            let measurementStart = Date()
            let audioDuration = try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds

            progressHandler?(
                .make(phase: .initializing, fraction: 0, modelDisplayName: job.modelDisplayName)
            )

            let whisperKit = try await prepareWhisperKit(
                modelName: job.whisperKitModelName,
                modelDisplayName: job.modelDisplayName,
                progressHandler: progressHandler
            )

            try Task.checkCancellation()

            guard FileManager.default.isReadableFile(atPath: job.audioFileURL.path) else {
                throw AppError.fileAccessDenied
            }

            let decodeOptions = makeDecodingOptions(languageID: job.languageID, vadEnabled: job.vadEnabled)

            progressHandler?(
                .make(phase: .convertingAudio, fraction: 0, modelDisplayName: job.modelDisplayName)
            )

            var completedText: String = ""
            whisperKit.segmentDiscoveryCallback = { segments in
                guard let partialText = TranscriptPartialTextBuilder.appendPresentableWindowText(
                    from: segments.map(\.text),
                    to: &completedText
                ) else {
                    return
                }

                let fraction = whisperKit.progress.fractionCompleted
                progressHandler?(
                    .make(
                        phase: .transcribing,
                        fraction: fraction > 0 ? fraction : 0,
                        modelDisplayName: job.modelDisplayName,
                        partialText: partialText
                    )
                )
                // Checkpoint intermediate results to disk (for recovery after a crash or quit)
                self.saveCheckpoint(text: partialText, for: job)
            }
            defer {
                whisperKit.segmentDiscoveryCallback = nil
            }

            // Process long audio in chunks (to avoid feeding it to WhisperKit all at once).
            let chunks = await splitAudioIntoChunks(url: job.audioFileURL, chunkDuration: job.chunkDuration)
            var allResults: [TranscriptionResult] = []
            var processedSeconds: TimeInterval = 0
            var totalSeconds: TimeInterval = chunks.count > 1
                ? (try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds) ?? Double(chunks.count)
                : Double(chunks.count)

            for (index, chunkURL) in chunks.enumerated() {
                try Task.checkCancellation()
                let results = try await whisperKit.transcribe(
                    audioPath: chunkURL.path,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        let localFraction = whisperKit.progress.fractionCompleted
                        let overall = totalSeconds > 0
                            ? min(1.0, (Double(index) + max(0, localFraction)) / Double(chunks.count))
                            : 0
                        progressHandler?(
                            .make(
                                phase: .transcribing,
                                fraction: overall,
                                modelDisplayName: job.modelDisplayName
                            )
                        )
                        // On cancellation, return false so WhisperKit stops its internal processing immediately.
                        return !Task.isCancelled
                    }
                )
                allResults.append(contentsOf: results)
                processedSeconds += (try? await AVURLAsset(url: chunkURL).load(.duration).seconds) ?? 0
            }

            try Task.checkCancellation()

            let merged = TranscriptionUtilities.mergeTranscriptionResults(allResults)
            progressHandler?(
                .make(phase: .finished, fraction: 1.0, modelDisplayName: job.modelDisplayName)
            )

            // Record RTF as log and diagnostic information.
            let elapsed = Date().timeIntervalSince(measurementStart)
            if let duration = audioDuration, duration > 0 {
                let rtf = elapsed / duration
                AppLogger.info(
                    "Transcription RTF: \(String(format: "%.3f", rtf)) (elapsed \(String(format: "%.1f", elapsed))s / audio \(String(format: "%.1f", duration))s)",
                    logger: AppLogger.transcription
                )
            } else {
                AppLogger.info(
                    "Transcription elapsed: \(String(format: "%.1f", elapsed))s (audio duration unknown)",
                    logger: AppLogger.transcription
                )
            }

            return mapToTranscript(
                merged,
                sourceFileName: job.sourceFileName,
                tokenizer: whisperKit.tokenizer,
                modelID: job.modelID,
                sourceFileFingerprint: AudioFileService.sha256(of: job.audioFileURL)
            )
        } catch is CancellationError {
            throw AppError.transcriptionCancelled
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.transcriptionFailedWithReason(error)
        }
    }

    private func prepareWhisperKit(
        modelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> WhisperKit {
        if let whisperKit, currentModelName == modelName {
            return whisperKit
        }

        AppDirectories.ensureDirectoriesExist()

        let modelPath = try resolveModelPath(
            modelName: modelName,
            modelDisplayName: modelDisplayName
        )

        guard modelAvailability.validateModelFolder(modelPath) else {
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "モデルファイルが不正です。ツールバーの「モデルをダウンロード」ボタンから再ダウンロードしてください。",
                    comment: "Invalid model files guidance"
                )
            )
        }

        progressHandler?(
            .make(phase: .loadingModel, fraction: 0, modelDisplayName: modelDisplayName)
        )

        do {
            let instance = try await loadWhisperKit(modelName: modelName, modelPath: modelPath)
            self.whisperKit = instance
            self.currentModelName = modelName
            return instance
        } catch {
            AppLogger.error(
                "Model load failed at \(modelPath.lastPathComponent): \(error.localizedDescription)",
                logger: AppLogger.transcription
            )
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "モデルの読み込みに失敗しました。ツールバーの「モデルをダウンロード」ボタンから再ダウンロードしてください。",
                    comment: "Model load failed guidance"
                )
            )
        }
    }

    private func resolveModelPath(
        modelName: String,
        modelDisplayName: String?
    ) throws -> URL {
        if let existingPath = modelAvailability.modelFolder(for: modelName) {
            AppLogger.info("Using cached model at \(existingPath.lastPathComponent)", logger: AppLogger.transcription)
            return existingPath
        }

        let displayName = modelDisplayName ?? modelName
        throw AppError.modelNotDownloaded(displayName)
    }

    private func loadWhisperKit(modelName: String, modelPath: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: AppDirectories.modelsDirectory,
            modelFolder: modelPath.path,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )

        return try await WhisperKit(config)
    }

    /// Languages for which WhisperKit can be given an explicit language code (ISO 639-1).
    /// IDs not included here fall back to automatic detection (detectLanguage).
    private static let explicitLanguageIDs: Set<String> = [
        "ja", "en", "zh", "ko", "fr", "de", "es", "it", "pt", "ru"
    ]

    /// Checkpoints intermediate results to disk.
    /// After a crash or app quit, processing can resume and recover from this file.
    private func saveCheckpoint(text: String, for job: TranscriptionJob) {
        guard !text.isEmpty else { return }
        let directory = AppDirectories.checkpointDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(job.id.uuidString).json")
        let payload: [String: Any] = [
            "jobID": job.id.uuidString,
            "sourceFileName": job.sourceFileName,
            "text": text,
            "updatedAt": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }


    /// Splits long audio into the given chunk length and returns temporary files.
    /// Returns the original file if splitting is unnecessary (already within the chunk length).
    private func splitAudioIntoChunks(url: URL, chunkDuration: TimeInterval) async -> [URL] {
        guard chunkDuration > 0 else { return [url] }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > chunkDuration else {
            return [url]
        }

        let chunkCount = Int(ceil(duration / chunkDuration))
        var outputURLs: [URL] = []
        for index in 0..<chunkCount {
            let start = Double(index) * chunkDuration
            let end = min(start + chunkDuration, duration)
            let outputURL = AppDirectories.checkpointDirectory
                .appendingPathComponent("chunk-\(index).m4a")
            try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: outputURL)

            let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
            export?.outputURL = outputURL
            export?.outputFileType = .m4a
            export?.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))

            let semaphore = DispatchSemaphore(value: 0)
            export?.exportAsynchronously { semaphore.signal() }
            semaphore.wait()
            if export?.status == .completed {
                outputURLs.append(outputURL)
            }
        }
        return outputURLs.isEmpty ? [url] : outputURLs
    }

    private func makeDecodingOptions(languageID: String, vadEnabled: Bool = false) -> DecodingOptions {

        if Self.explicitLanguageIDs.contains(languageID) {

            return DecodingOptions(
                language: languageID,
                usePrefillPrompt: true,
                detectLanguage: false,
                skipSpecialTokens: true
            )
        }
        return DecodingOptions(
            language: nil,
            usePrefillPrompt: false,
            detectLanguage: true,
            skipSpecialTokens: true
        )
    }

    private static func decodeWordTokens(_ tokens: [Int], using tokenizer: WhisperTokenizer) -> String {
        let wordTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        guard !wordTokens.isEmpty else { return "" }
        return TranscriptTextSanitizer.sanitize(tokenizer.decode(tokens: wordTokens))
    }

    private static func mapWhisperKitSegment(
        _ segment: TranscriptionSegment,
        tokenizer: WhisperTokenizer
    ) -> TranscriptSegment {
        let text = TranscriptTextSanitizer.presentableText(from: segment.text)
            ?? decodeWordTokens(segment.tokens, using: tokenizer)
        return TranscriptSegment(
            startTime: TimeInterval(segment.start),
            endTime: TimeInterval(segment.end),
            text: text
        )
    }

    private static func mapWhisperKitSegment(_ segment: TranscriptionSegment) -> TranscriptSegment {
        TranscriptSegment(
            startTime: TimeInterval(segment.start),
            endTime: TimeInterval(segment.end),
            text: TranscriptTextSanitizer.presentableText(from: segment.text) ?? ""
        )
    }

    private func mapToTranscript(
        _ result: TranscriptionResult,
        sourceFileName: String,
        tokenizer: WhisperTokenizer?,
        modelID: String?,
        sourceFileFingerprint: String?
    ) -> Transcript {
        let segments: [TranscriptSegment]
        if let tokenizer {
            segments = result.segments.map { Self.mapWhisperKitSegment($0, tokenizer: tokenizer) }
        } else {
            segments = result.segments.map(Self.mapWhisperKitSegment)
        }

        let fullText = TranscriptTextSanitizer.presentableText(from: result.text)
            ?? TranscriptTextSanitizer.sanitize(result.text)

        return Transcript(
            sourceFileName: sourceFileName,
            language: result.language.isEmpty ? nil : result.language,
            fullText: fullText,
            segments: segments,
            modelID: modelID,
            sourceFileFingerprint: sourceFileFingerprint
        )
    }
}
