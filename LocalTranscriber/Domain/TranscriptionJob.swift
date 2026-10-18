import Foundation

struct TranscriptionJob: Identifiable, Sendable {
    let id: UUID
    let audioFileURL: URL
    let sourceFileName: String
    let modelID: String
    let whisperKitModelName: String
    let modelDisplayName: String
    let languageID: String
    let vadEnabled: Bool
    /// Chunk length in seconds for splitting long audio. Defaults to 600 seconds (10 minutes).
    let chunkDuration: TimeInterval

    init(
        id: UUID = UUID(),
        audioFileURL: URL,
        sourceFileName: String,
        modelID: String,
        whisperKitModelName: String,
        modelDisplayName: String,
        languageID: String,
        vadEnabled: Bool = false,
        chunkDuration: TimeInterval = 600
    ) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.sourceFileName = sourceFileName
        self.modelID = modelID
        self.whisperKitModelName = whisperKitModelName
        self.modelDisplayName = modelDisplayName
        self.languageID = languageID
        self.vadEnabled = vadEnabled
        self.chunkDuration = chunkDuration
    }
}
