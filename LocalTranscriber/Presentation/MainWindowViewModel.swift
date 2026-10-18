@MainActor
final class OperationCoordinator {
    enum Operation: Equatable {
        case importing
        case transcription
        case modelDownload
        case playback
    }

    private(set) var activeOperation: Operation?

    func canStart(_ operation: Operation) -> Bool {
        activeOperation == nil || activeOperation == operation
    }

    @discardableResult
    func start(_ operation: Operation) -> Bool {
        guard canStart(operation) else { return false }
        activeOperation = operation
        return true
    }

    func end(_ operation: Operation) {
        if activeOperation == operation {
            activeOperation = nil
        }
    }
}

import AVFoundation
import SwiftUI

// MARK: - Model download coordination

@MainActor
final class ModelDownloadCoordinator {
    struct State {
        var isDownloading = false
        var activeID: UUID?
    }

    private(set) var state = State()

    func begin() -> UUID? {
        guard !state.isDownloading else { return nil }
        let id = UUID()
        state.isDownloading = true
        state.activeID = id
        return id
    }

    func finish(_ id: UUID) {
        guard state.activeID == id else { return }
        state.isDownloading = false
        state.activeID = nil
    }

    func isActive(_ id: UUID) -> Bool {
        state.activeID == id && state.isDownloading
    }
}

@MainActor
struct AppDependencies {

    var transcriber: any Transcriber = WhisperKitTranscriber()
    var audioFileService: AudioFileService = AudioFileService()
    var audioImportService: AudioImportService = AudioImportService()
    var exportService: ExportService = ExportService()
    var fileAccess: SecurityScopedFileAccess = .shared
    var settings: AppSettings = AppSettings.shared
    var modelAvailability: ModelAvailabilityService = ModelAvailabilityService()
    var modelDownloadService: ModelDownloadService = ModelDownloadService()
    var audioPlayer: AudioPlayerService? = nil
    var historyStore: HistoryStore = HistoryStore()
    var savePanelPresenter: any SavePanelPresenting = NSSavePanelPresenter()

    static let shared = AppDependencies()
}

@MainActor
final class MainWindowViewModel: ObservableObject {
    @Published var uiState: TranscriptionUIState = .idle
    @Published var progressDisplay: TranscriptionProgressDisplay = .idle()
    @Published var selectedFile: AudioFileInfo?
    @Published var transcriptText: String = ""
    @Published var currentTranscript: Transcript?
    @Published var playingSegmentID: UUID?
    @Published var playbackPositionText: String = ""
    @Published var isSegmentPaused = false
    @Published var isEditingTranscript = false
    @Published var errorMessage: String?
    @Published var inlineErrorTitle: String?
    @Published var inlineErrorMessage: String?
    @Published var canRetryError = false
    @Published var criticalErrorTitle: String?
    @Published var criticalErrorMessage: String?
    @Published var downloadedModelIDs: Set<String> = []
    @Published var toast: ToastMessage?

    private enum RecoverableAction: Equatable {
        case transcription
        case modelDownload
        case fileImport(url: URL, preferredFileName: String?)
        case export(format: ExportFormat)
    }

    private enum ErrorContext {
        case fileImport(url: URL, preferredFileName: String?)
        case transcription
        case modelDownload
        case export(ExportFormat)
        case general
    }

    private var lastRecoverableAction: RecoverableAction?
    private var activeJobID: UUID?
    private var activeModelDownloadID: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var lastAnnouncedPhase: TranscriptionProgressPhase?
    private var toastDismissTask: Task<Void, Never>?

    private let modelDownloadCoordinator = ModelDownloadCoordinator()

    private let transcriber: Transcriber
    private let audioFileService: AudioFileService
    private let audioImportService: AudioImportService
    private let exportService: ExportService
    private let fileAccess: SecurityScopedFileAccess
    private let savePanelPresenter: any SavePanelPresenting
    private let settings: any AppSettingsProviding
    private let modelAvailability: ModelAvailabilityService
    private let modelDownloadService: ModelDownloadService
    private let audioPlayer: AudioPlayerService
    private let historyStore: HistoryStore

    init(
        transcriber: Transcriber = WhisperKitTranscriber(),
        audioFileService: AudioFileService = AudioFileService(),
        audioImportService: AudioImportService = AudioImportService(),
        exportService: ExportService = ExportService(),
        fileAccess: SecurityScopedFileAccess = .shared,
        savePanelPresenter: any SavePanelPresenting = NSSavePanelPresenter(),
        settings: any AppSettingsProviding = AppSettings.shared,
        modelAvailability: ModelAvailabilityService = ModelAvailabilityService(),
        modelDownloadService: ModelDownloadService = ModelDownloadService(),
        audioPlayer: AudioPlayerService? = nil,
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.transcriber = transcriber
        self.audioFileService = audioFileService
        self.audioImportService = audioImportService
        self.exportService = exportService
        self.fileAccess = fileAccess
        self.savePanelPresenter = savePanelPresenter
        self.settings = settings
        self.modelAvailability = modelAvailability
        self.modelDownloadService = modelDownloadService
        self.audioPlayer = audioPlayer ?? AudioPlayerService()
        self.historyStore = historyStore
        self.audioPlayer.onPlaybackTimeUpdate = { [weak self] current, duration in
            Task { @MainActor in
                self?.updatePlaybackPosition(current: current, duration: duration)
            }
        }
        refreshModelAvailability()
    }

    /// Initializer that injects all dependencies at once via AppDependencies.
    init(dependencies: AppDependencies) {
        self.transcriber = dependencies.transcriber
        self.audioFileService = dependencies.audioFileService
        self.audioImportService = dependencies.audioImportService
        self.exportService = dependencies.exportService
        self.fileAccess = dependencies.fileAccess
        self.savePanelPresenter = dependencies.savePanelPresenter
        self.settings = dependencies.settings
        self.modelAvailability = dependencies.modelAvailability
        self.modelDownloadService = dependencies.modelDownloadService
        self.audioPlayer = dependencies.audioPlayer ?? AudioPlayerService()
        self.historyStore = dependencies.historyStore
        refreshModelAvailability()
    }

    private let operationCoordinator = OperationCoordinator()

    /// Whether a model download is in progress. A single state derived from uiState + progressDisplay.
    var isDownloadingModel: Bool {
        uiState == .preparing && progressDisplay.phase == .downloadingModel
    }

    /// Test only: simulates the model-downloading state.
    /// Not used in production code (to keep the state machine consistent).
    func simulateModelDownloadForTesting() {
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(update: .make(phase: .downloadingModel, fraction: 0))
    }

    var isBusy: Bool {
        operationCoordinator.activeOperation != nil || isDownloadingModel
    }

    var canStartTranscription: Bool {
        guard selectedFile != nil,
              !isBusy,
              let model = settings.selectedModel else {
            return false
        }
        return isModelDownloaded(model)
    }

    var canDownloadSelectedModel: Bool {
        guard !isBusy,
              let model = settings.selectedModel else {
            return false
        }
        return !isModelDownloaded(model)
    }

    var startTranscriptionDisabledReason: String? {
        if isBusy {
            return NSLocalizedString("文字起こし処理中です", comment: "Transcription is busy")
        }
        if selectedFile == nil {
            return NSLocalizedString("音声ファイルを選択してください", comment: "Select an audio file")
        }
        if settings.selectedModel == nil {
            return NSLocalizedString("モデルを選択してください", comment: "Select a model")
        }
        if let model = settings.selectedModel, !isModelDownloaded(model) {
            return NSLocalizedString("モデルをダウンロードしてください", comment: "Download the selected model")
        }
        return nil
    }

    var modelDownloadDisabledReason: String? {
        if isBusy {
            return NSLocalizedString("処理中です", comment: "Operation in progress")
        }
        if settings.selectedModel == nil {
            return NSLocalizedString("モデルを選択してください", comment: "Select a model")
        }
        return nil
    }

    var shouldShowModelDownloadButton: Bool {
        guard let model = settings.selectedModel else {
            return false
        }
        return !isModelDownloaded(model)
    }

    var modelDownloadGuidance: String? {
        shouldShowModelDownloadButton
            ? NSLocalizedString(
                "初回はモデルのダウンロードが必要です（音声は端末内で処理し、通信はダウンロード時のみ）",
                comment: "Model download onboarding guidance"
            )
            : nil
    }

    var canCancel: Bool {
        isBusy
    }

    var cancelActionAccessibilityLabel: String {
        if isDownloadingModel {
            return NSLocalizedString("ダウンロードをキャンセル", comment: "Cancel model download accessibility label")
        }
        return NSLocalizedString("文字起こしをキャンセル", comment: "Cancel transcription accessibility label")
    }

    var cancelActionHelp: String {
        if isDownloadingModel {
            return NSLocalizedString("ダウンロードをキャンセル（Esc）", comment: "Cancel model download shortcut help")
        }
        return NSLocalizedString("文字起こしをキャンセル（Esc）", comment: "Cancel transcription shortcut help")
    }

    var cancelMenuTitle: String {
        cancelActionAccessibilityLabel
    }

    var canExport: Bool {
        currentTranscript != nil && !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyTranscript: Bool {
        canExport
    }

    static func hasPlayableSegments(in transcript: Transcript) -> Bool {
        transcript.segments.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Fetches the temporary Transcript used for crash recovery.
    func temporaryTranscriptForRecovery() -> Transcript? {
        historyStore.loadTemporary()
    }

    /// Deletes the temporary recovery Transcript.
    func clearTemporaryTranscript() {
        historyStore.clearTemporary()
    }

    /// Restores the temporary crash-recovery Transcript into the current state.
    func restoreTranscript(_ transcript: Transcript) {
        currentTranscript = transcript
        transcriptText = transcript.fullText
        isEditingTranscript = !Self.hasPlayableSegments(in: transcript)
        uiState = .done
        progressDisplay = .done()
        confirmFileImport = false
        pendingFileImport = nil
    }

    func refreshModelAvailability() {
        downloadedModelIDs = Set(
            settings.models
                .filter { modelAvailability.isDownloaded(whisperKitModelName: $0.whisperKitModelName) }
                .map(\.id)
        )
    }

    func isModelDownloaded(_ model: ModelOption) -> Bool {
        downloadedModelIDs.contains(model.id)
    }

    /// Deletes the selected model if it has been downloaded.
    func deleteSelectedModel() {
        guard let model = settings.selectedModel,
              isModelDownloaded(model) else { return }
        do {
            try modelDownloadService.deleteModel(whisperKitModelName: model.whisperKitModelName)
            refreshModelAvailability()
            showToast(
                String(
                    format: NSLocalizedString("モデル「%@」を削除しました", comment: "Model deleted toast"),
                    model.displayName
                )
            )
        } catch {
            handleError(error, context: .general)
        }
    }

    /// Returns the model's disk usage as display text. nil if not downloaded.
    func modelDiskUsageText(_ model: ModelOption) -> String? {
        guard isModelDownloaded(model) else { return nil }
        let bytes = modelAvailability.diskUsage(whisperKitModelName: model.whisperKitModelName)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func modelDownloadSuccessToastMessage() -> String {
        if selectedFile != nil {
            return NSLocalizedString(
                "モデルのダウンロードが完了しました。文字起こしを開始できます。",
                comment: "Model download success toast when file is selected"
            )
        }
        return NSLocalizedString(
            "モデルのダウンロードが完了しました。音声ファイルを選択してください。",
            comment: "Model download success toast when no file is selected"
        )
    }

    func downloadSelectedModel() {
        guard let model = settings.selectedModel,
              canDownloadSelectedModel else {
            return
        }

        let downloadID = UUID()
        activeModelDownloadID = downloadID
        clearErrors()
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .downloadingModel, fraction: 0, modelDisplayName: model.localizedDisplayName)
        )
        lastAnnouncedPhase = nil

        modelDownloadTask = Task {
            do {
                _ = try await modelDownloadService.downloadIfNeeded(
                    whisperKitModelName: model.whisperKitModelName,
                    modelDisplayName: model.localizedDisplayName
                ) { update in
                    Task { @MainActor in
                        guard self.activeModelDownloadID == downloadID else { return }
                        self.applyModelDownloadProgress(update)
                    }
                }

                refreshModelAvailability()
                if activeModelDownloadID == downloadID {
                    uiState = .idle
                    progressDisplay = .idle()
                    announcePhaseIfNeeded(.finished)
                    showToast(modelDownloadSuccessToastMessage())
                    AppLogger.info("Model download completed: \(model.displayName)", logger: AppLogger.transcription)
                }
            } catch {
                if activeModelDownloadID == downloadID, !Task.isCancelled {
                    handleError(error, context: .modelDownload)
                }
            }

            if activeModelDownloadID == downloadID {
                activeModelDownloadID = nil
                modelDownloadTask = nil
            }
        }
    }

    @Published var confirmFileImport = false
    @Published var pendingFileImport: (url: URL, preferredFileName: String?)?

    var hasExistingResult: Bool {
        (currentTranscript?.fullText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
    }

    /// Indicates whether the content in edit mode has changed from the original transcript.
    /// Dirty state checked before closing the window or replacing the file.
    var hasUnsavedChanges: Bool {
        guard let transcript = currentTranscript else { return false }
        let normalizedEdited = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOriginal = transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedEdited != normalizedOriginal
    }

    func selectFile(url: URL, preferredFileName: String? = nil) {
        // Replacing the file during transcription or model download is not allowed.
        guard !isBusy else {
            AppLogger.info("File selection ignored while busy", logger: AppLogger.fileAccess)
            return
        }

        clearErrors()

        if hasExistingResult || hasUnsavedChanges {
            pendingFileImport = (url, preferredFileName)
            confirmFileImport = true
            return
        }

        applyFileImport(url: url, preferredFileName: preferredFileName)
    }

    func applyPendingFileImport() {
        guard let pending = pendingFileImport else { return }
        confirmFileImport = false
        pendingFileImport = nil
        applyFileImport(url: pending.url, preferredFileName: pending.preferredFileName)
    }

    func cancelPendingFileImport() {
        confirmFileImport = false
        pendingFileImport = nil
    }

    private func applyFileImport(url: URL, preferredFileName: String?) {
        do {
            let resolvedPreferredFileName = preferredFileName ?? preferredImportFileName(for: url)
            let importedURL = try audioImportService.importFile(
                from: url,
                preferredFileName: resolvedPreferredFileName
            )
            let info = try audioFileService.validate(
                url: importedURL,
                preferredFileName: resolvedPreferredFileName
            )
            removePreviousSandboxCopyIfNeeded()
            stopPlayback()
            isEditingTranscript = false
            currentTranscript = nil
            transcriptText = ""
            selectedFile = info
            uiState = .idle
            progressDisplay = .idle()
        } catch {
            handleError(error, context: .fileImport(url: url, preferredFileName: preferredFileName))
        }
    }

    /// When replacing the file, deletes the old sandbox copy left in Imports/.
    /// Deletion is limited to thin sandbox copies (under AppDirectories.importsDirectory).
    private func removePreviousSandboxCopyIfNeeded() {
        guard let previousURL = selectedFile?.url else { return }
        let importsPath = AppDirectories.importsDirectory.standardizedFileURL.path
        let previousPath = previousURL.standardizedFileURL.path
        guard previousPath.hasPrefix(importsPath + "/"),
              FileManager.default.fileExists(atPath: previousPath) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: previousURL)
            AppLogger.info(
                "Removed previous sandbox copy: \(previousURL.lastPathComponent)",
                logger: AppLogger.fileAccess
            )
        } catch {
            AppLogger.error(
                "Failed to remove previous sandbox copy: \(previousURL.lastPathComponent)",
                logger: AppLogger.fileAccess
            )
        }
    }

    private func preferredImportFileName(for url: URL) -> String? {
        let resolvedName = AudioFileNameResolver.resolve(sourceURL: url)
        guard resolvedName != url.lastPathComponent else {
            return nil
        }
        guard DropImportService.hasSupportedExtension(
            resolvedName,
            supportedExtensions: settings.supportedExtensions
        ) else {
            return nil
        }
        return resolvedName
    }

    func startTranscription() {
        guard let file = selectedFile,
              let model = settings.selectedModel else {
            let message = AppError.invalidConfiguration.errorDescription
                ?? NSLocalizedString("アプリ設定が不正です。", comment: "Invalid configuration")
            presentCriticalError(
                title: NSLocalizedString("設定エラー", comment: "Configuration error title"),
                message: message
            )
            return
        }

        guard isModelDownloaded(model) else {
            let message = AppError.modelNotDownloaded(model.localizedDisplayName).errorDescription
                ?? NSLocalizedString(
                    "モデルがダウンロードされていません。",
                    comment: "Model is not downloaded"
            )
            presentInlineError(
                title: NSLocalizedString("モデル未ダウンロード", comment: "Model not downloaded title"),
                message: message,
                canRetry: false,
                action: nil
            )
            return
        }

        guard operationCoordinator.start(.transcription) else {
            presentInlineError(
                title: NSLocalizedString("処理中", comment: "Busy title"),
                message: NSLocalizedString("別の処理を実行中のため開始できません。", comment: "Busy message"),
                canRetry: false,
                action: nil
            )
            return
        }

        settings.persist()
        clearErrors()
        stopPlayback()
        isEditingTranscript = false
        transcriptText = ""
        currentTranscript = nil
        uiState = .preparing
        progressDisplay = TranscriptionProgressDisplay.from(
            update: .make(phase: .initializing, fraction: 0, modelDisplayName: model.localizedDisplayName)
        )
        lastAnnouncedPhase = nil

        let job = TranscriptionJob(
            audioFileURL: file.url,
            sourceFileName: file.fileName,
            modelID: model.id,
            whisperKitModelName: model.whisperKitModelName,
            modelDisplayName: model.localizedDisplayName,
            languageID: settings.selectedLanguageID,
            vadEnabled: settings.vadEnabled
        )

        activeJobID = job.id

        transcriptionTask = Task {
            do {
                var transcript = try await transcriber.transcribe(job) { update in
                    Task { @MainActor in
                        guard self.activeJobID == job.id else { return }
                        self.applyProgressUpdate(update)
                    }
                }

                transcript = await Self.transcriptWithPlaybackSegments(
                    transcript,
                    audioURL: file.url
                )

                guard activeJobID == job.id else { return }
                currentTranscript = transcript
                try? historyStore.save(transcript)
                try? historyStore.saveTemporary(transcript)
                transcriptText = TranscriptTextSanitizer.presentableText(from: transcript.fullText)
                    ?? TranscriptTextSanitizer.sanitize(transcript.fullText)
                isEditingTranscript = !Self.hasPlayableSegments(in: transcript)
                audioPlayer.load(url: file.url)
                uiState = .done
                progressDisplay = .done()
                refreshModelAvailability()
                announcePhaseIfNeeded(.finished)
                AppLogger.info("Transcription completed for \(file.fileName)", logger: AppLogger.transcription)
            } catch {
                if activeJobID == job.id, !Task.isCancelled {
                    handleError(error, context: .transcription)
                }
            }

            if activeJobID == job.id {
                activeJobID = nil
                transcriptionTask = nil
            }
            operationCoordinator.end(.transcription)
        }
    }

    /// Cancels transcription only (not model downloads).
    func cancelTranscription() {
        if let jobID = activeJobID {
            Task { await transcriber.cancel(jobID: jobID) }
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeJobID = nil
        operationCoordinator.end(.transcription)

        uiState = .idle
        progressDisplay = .idle()
        lastAnnouncedPhase = nil
    }

    /// Cancels model download only (not transcription).
    func cancelModelDownload() {
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        activeModelDownloadID = nil
        uiState = .idle
        progressDisplay = .idle()
        lastAnnouncedPhase = nil
        AccessibilityNotification.Announcement(
            NSLocalizedString("処理をキャンセルしました。", comment: "Accessibility announcement for cancellation")
        ).post()
    }

    /// Syncs Full Text edits with currentTranscript's fullText.
    /// If a segment's text is empty, applies the edited full text.
    func updateTranscriptText(_ newText: String) {
        transcriptText = newText
        guard var transcript = currentTranscript else { return }
        transcript.fullText = newText
        // So the segment view does not diverge when switching back from full-text editing,
        // also sync text when there is only one segment (the full text is held in a single segment).
        if transcript.segments.count == 1 {
            transcript.segments[0].text = newText
        }
        currentTranscript = transcript
    }

    /// Updates a segment's text and syncs it to currentTranscript and the full text.
    func updateSegmentText(id: UUID, text: String) {
        guard var transcript = currentTranscript else { return }
        if let index = transcript.segments.firstIndex(where: { $0.id == id }) {
            transcript.segments[index].text = text
            currentTranscript = transcript
            transcriptText = transcript.fullText
        }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
        showToast(NSLocalizedString("文字起こし結果をコピーしました", comment: "Transcript copied toast"))
    }

    func showToast(_ text: String, icon: String = "checkmark.circle.fill", action: (label: String, handler: @Sendable () -> Void)? = nil) {
        toastDismissTask?.cancel()
        toast = ToastMessage(text: text, icon: icon, action: action)
        // Action buttons need a longer window so users can click before auto-dismiss.
        let dismissNanoseconds: UInt64 = action == nil ? 2_500_000_000 : 7_000_000_000
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: dismissNanoseconds)
            if !Task.isCancelled {
                toast = nil
            }
        }
    }

    private func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    func playSegment(_ segment: TranscriptSegment) {
        guard let file = selectedFile else { return }

        if audioPlayer.loadedURL != file.url {
            audioPlayer.load(url: file.url)
        }

        playingSegmentID = segment.id
        let segmentID = segment.id
        playbackPositionText = Self.remainingTimeText(
            current: 0,
            duration: segment.endTime - segment.startTime
        )
        audioPlayer.playSegment(
            start: segment.startTime,
            end: segment.endTime
        ) { [weak self] in
            guard let self else { return }
            if self.playingSegmentID == segmentID {
                self.playingSegmentID = nil
                self.playbackPositionText = ""
            }
        }
    }

    /// Displays the remaining time from the current playback position and the segment length.
    func updatePlaybackPosition(current: TimeInterval, duration: TimeInterval) {
        playbackPositionText = Self.remainingTimeText(current: current, duration: duration)
    }

    private static func remainingTimeText(current: TimeInterval, duration: TimeInterval) -> String {
        let remaining = max(0, duration - current)
        let totalSeconds = Int(remaining.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    func pausePlayback() {
        audioPlayer.pause()
        isSegmentPaused = true
    }

    func resumePlayback() {
        audioPlayer.resume()
        isSegmentPaused = false
    }

    func stopPlayback() {
        audioPlayer.stop()
        playingSegmentID = nil
        isSegmentPaused = false
    }

    func exportTranscript(format: ExportFormat) {
        guard var transcript = currentTranscript else { return }
        transcript.fullText = transcriptText
        // On export (reflecting the latest edits), update updatedAt and record the edited state.
        transcript.updatedAt = Date()
        currentTranscript = transcript

        let savedExportDirectory = fileAccess.loadLastExportDirectory()
        var didBeginSavedDirectoryAccess = false

        if let savedDirectory = savedExportDirectory {
            do {
                try fileAccess.beginAccess(url: savedDirectory)
                didBeginSavedDirectoryAccess = true
            } catch {
                AppLogger.info(
                    "Skipped last export directory restore: \(error.localizedDescription)",
                    logger: AppLogger.fileAccess
                )
            }
        }

        defer {
            if didBeginSavedDirectoryAccess, let savedDirectory = savedExportDirectory {
                fileAccess.endAccess(url: savedDirectory)
            }
        }

        let url = savePanelPresenter.presentSavePanel(
            defaultFileName: defaultExportFilename(for: transcript, format: format),
            allowedContentTypes: [UTType(filenameExtension: format.fileExtension) ?? .plainText],
            initialDirectoryURL: didBeginSavedDirectoryAccess ? savedExportDirectory : nil
        )
        guard let url else { return }

        // On success, save the bookmark as the initial directory for next time
        fileAccess.saveLastExportDirectoryBookmark(for: url.deletingLastPathComponent())

        do {
            try exportService.write(transcript: transcript, format: format, to: url)
            showToast(
                String(
                    format: NSLocalizedString("保存しました: %@", comment: "Export completed toast"),
                    url.lastPathComponent
                ),
                action: (
                    label: NSLocalizedString("Finder で表示", comment: "Reveal in Finder toast action"),
                    handler: { [weak self] in
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        Task { @MainActor in
                            self?.dismissToast()
                        }
                    }
                )
            )
            AppLogger.info("Exported \(format.displayName) to \(url.lastPathComponent)", logger: AppLogger.export)
        } catch {
            handleError(error, context: .export(format))
        }
    }

    func dismissInlineError() {
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        lastRecoverableAction = nil
        if criticalErrorMessage == nil {
            errorMessage = nil
        }
        if case .error = uiState {
            uiState = .idle
        }
    }

    func dismissCriticalError() {
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        errorMessage = nil
        uiState = .idle
    }

    func retryLastAction() {
        guard let action = lastRecoverableAction else { return }
        clearErrors()
        switch action {
        case .transcription:
            startTranscription()
        case .modelDownload:
            downloadSelectedModel()
        case .fileImport(let url, let preferredFileName):
            selectFile(url: url, preferredFileName: preferredFileName)
        case .export(let format):
            exportTranscript(format: format)
        }
    }

    private func applyModelDownloadProgress(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)
        uiState = .preparing
        announcePhaseIfNeeded(update.phase)
    }

    private func applyProgressUpdate(_ update: TranscriptionProgressUpdate) {
        progressDisplay = TranscriptionProgressDisplay.from(update: update)

        if let partialText = update.partialText,
           let presentable = TranscriptTextSanitizer.presentableText(from: partialText) {
            transcriptText = presentable
        }

        switch update.phase {
        case .transcribing, .convertingAudio:
            uiState = .transcribing
        case .loadingModel, .initializing:
            uiState = .preparing
        case .finished:
            break
        case .downloadingModel:
            break
        }

        announcePhaseIfNeeded(update.phase)
    }

    private func announcePhaseIfNeeded(_ phase: TranscriptionProgressPhase) {
        let majorPhases: Set<TranscriptionProgressPhase> = [
            .downloadingModel, .loadingModel, .transcribing, .finished
        ]
        guard majorPhases.contains(phase), lastAnnouncedPhase != phase else { return }
        lastAnnouncedPhase = phase
        AccessibilityNotification.Announcement(phase.localizedDisplayName).post()
    }

    private func defaultExportFilename(for transcript: Transcript, format: ExportFormat) -> String {
        let stem = URL(fileURLWithPath: transcript.sourceFileName).deletingPathExtension().lastPathComponent
        return "\(stem.isEmpty ? "transcript" : stem).\(format.fileExtension)"
    }

    private func clearErrors() {
        errorMessage = nil
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        lastRecoverableAction = nil
    }

    private func presentInlineError(
        title: String,
        message: String,
        canRetry: Bool,
        action: RecoverableAction?
    ) {
        errorMessage = message
        inlineErrorTitle = title
        inlineErrorMessage = message
        canRetryError = canRetry
        lastRecoverableAction = canRetry ? action : nil
        criticalErrorTitle = nil
        criticalErrorMessage = nil
        uiState = .idle
    }

    private func presentCriticalError(title: String, message: String) {
        errorMessage = message
        criticalErrorTitle = title
        criticalErrorMessage = message
        inlineErrorTitle = nil
        inlineErrorMessage = nil
        canRetryError = false
        lastRecoverableAction = nil
        if uiState != .preparing && uiState != .transcribing {
            uiState = .idle
        }
    }

    private func handleError(_ error: Error, context: ErrorContext) {
        let message = ErrorMapper.userMessage(for: error)

        // Log the underlying error (technical details), kept separate from the user-facing message.
        // If the underlying error is AppError.transcriptionFailedWithReason / AppError.exportFailedWithReason,
        // log the original reason; otherwise log the error itself.
        let logError: Error
        if let appError = error as? AppError {
            switch appError {
            case .transcriptionFailedWithReason(let reason), .exportFailedWithReason(let reason):
                logError = reason
            default:
                logError = error
            }
        } else {
            logError = error
        }
        AppLogger.error("\(logError)", logger: AppLogger.general)

        if isCriticalError(error) {
            presentCriticalError(title: criticalTitle(for: error), message: message)
        } else {
            let info = inlineErrorInfo(for: error, context: context)
            presentInlineError(
                title: info.title,
                message: message,
                canRetry: info.canRetry,
                action: info.action
            )
        }
        // Also announce cancellation and failure via VoiceOver
        AccessibilityNotification.Announcement(message).post()
    }

    private func isCriticalError(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        switch appError {
        case .invalidConfiguration, .bookmarkResolutionFailed:
            return true
        default:
            return false
        }
    }

    private func criticalTitle(for error: Error) -> String {
        guard let appError = error as? AppError else {
            return NSLocalizedString("エラー", comment: "Generic error title")
        }
        switch appError {
        case .invalidConfiguration:
            return NSLocalizedString("設定エラー", comment: "Configuration error title")
        case .bookmarkResolutionFailed:
            return NSLocalizedString("ファイルアクセスエラー", comment: "File access error title")
        default:
            return NSLocalizedString("エラー", comment: "Generic error title")
        }
    }

    private func inlineErrorInfo(
        for error: Error,
        context: ErrorContext
    ) -> (title: String, canRetry: Bool, action: RecoverableAction?) {
        switch context {
        case .fileImport(let url, let preferredFileName):
            return (
                NSLocalizedString("ファイルの読み込みエラー", comment: "File import error title"),
                true,
                .fileImport(url: url, preferredFileName: preferredFileName)
            )
        case .transcription:
            return (NSLocalizedString("文字起こしエラー", comment: "Transcription error title"), true, .transcription)
        case .modelDownload:
            return (
                NSLocalizedString("モデルのダウンロードエラー", comment: "Model download error title"),
                true,
                .modelDownload
            )
        case .export(let format):
            return (NSLocalizedString("エクスポートエラー", comment: "Export error title"), true, .export(format: format))
        case .general:
            if let appError = error as? AppError, case .modelNotDownloaded = appError {
                return (NSLocalizedString("モデル未ダウンロード", comment: "Model not downloaded title"), false, nil)
            }
            return (NSLocalizedString("エラー", comment: "Generic error title"), false, nil)
        }
    }

    private static func transcriptWithPlaybackSegments(
        _ transcript: Transcript,
        audioURL: URL
    ) async -> Transcript {
        let segments = transcript.segments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard segments.isEmpty,
              !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            var updated = transcript
            updated.segments = segments
            return updated
        }

        let asset = AVURLAsset(url: audioURL)
        guard let duration = try? await asset.load(.duration).seconds,
              duration > 0 else {
            return transcript
        }

        var updated = transcript
        updated.segments = [
            TranscriptSegment(
                startTime: 0,
                endTime: duration,
                text: transcript.fullText
            )
        ]
        return updated
    }
}

import UniformTypeIdentifiers

// MARK: - Save panel abstraction

/// Abstracts creating and showing NSSavePanel so it can be replaced in tests.
protocol SavePanelPresenting {
    func presentSavePanel(defaultFileName: String, allowedContentTypes: [UTType], initialDirectoryURL: URL?) -> URL?
}

struct NSSavePanelPresenter: SavePanelPresenting {
    func presentSavePanel(defaultFileName: String, allowedContentTypes: [UTType], initialDirectoryURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = allowedContentTypes
        panel.directoryURL = initialDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}
