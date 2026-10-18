import Foundation

/// A recognized word with its timing and the model's confidence in it.
struct TranscriptWord: Codable, Equatable, Sendable {
    /// Words scoring below this are flagged for review in the editor.
    static let lowConfidenceThreshold = 0.5

    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    /// Model confidence from 0 to 1: the geometric mean of the word's token probabilities.
    /// It shows how sure the model was, not whether the word is correct.
    let probability: Double

    var isLowConfidence: Bool {
        probability < Self.lowConfidenceThreshold
    }
}

struct TranscriptSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String {
        // Word scores describe the recognized text, so they no longer apply once it is edited.
        didSet {
            if text != oldValue {
                words = nil
            }
        }
    }
    /// Per-word timing and confidence. nil when the model produced no word timings,
    /// for transcripts saved before scores were recorded, and after the text is edited.
    var words: [TranscriptWord]?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        words: [TranscriptWord]? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }

    var lowConfidenceWords: [TranscriptWord] {
        words?.filter(\.isLowConfidence) ?? []
    }

    var formattedStartTime: String {
        Self.formatDisplayTimestamp(startTime, separator: ".")
    }

    var accessibilityStartTimestamp: String {
        Self.formatAccessibilityTimestamp(startTime)
    }

    private static func formatDisplayTimestamp(_ time: TimeInterval, separator: String) -> String {
        let totalMilliseconds = max(0, Int(time * 1000))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, seconds, milliseconds)
    }

    /// Spells out durations (e.g. "1 minute, 5 seconds") for VoiceOver. Leading zero units are dropped,
    /// matching the earlier hand-built format. Uses the app's active localization rather than the system
    /// region so the spoken duration matches the UI language.
    private static let accessibilityDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .dropLeading
        var calendar = Calendar.current
        calendar.locale = Bundle.main.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        formatter.calendar = calendar
        return formatter
    }()

    private static func formatAccessibilityTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return accessibilityDurationFormatter.string(from: TimeInterval(totalSeconds)) ?? "\(totalSeconds)"
    }
}
