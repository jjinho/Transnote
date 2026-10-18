import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    /// Schema version of the JSON export.
    /// Increment when fields are added in the future.
    static let currentSchemaVersion = 1

    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// Model ID used for transcription (the model setting's `id`).
    var modelID: String?
    /// Fingerprint (SHA256) identifying the source audio file.
    var sourceFileFingerprint: String?
    /// Date and time of the last edit (nil if unedited).
    var updatedAt: Date?
    let schemaVersion: Int

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        modelID: String? = nil,
        sourceFileFingerprint: String? = nil,
        updatedAt: Date? = nil,
        schemaVersion: Int = Transcript.currentSchemaVersion
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.modelID = modelID
        self.sourceFileFingerprint = sourceFileFingerprint
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }

    // Use decodeIfPresent so existing JSON (without schemaVersion) can still be loaded.
    private enum CodingKeys: String, CodingKey {
        case id, sourceFileName, language, createdAt, fullText, segments, modelID, sourceFileFingerprint, updatedAt, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fullText = try container.decode(String.self, forKey: .fullText)
        segments = try container.decode([TranscriptSegment].self, forKey: .segments)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        sourceFileFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFileFingerprint)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    }
}
