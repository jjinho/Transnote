import Foundation

struct ExportService {
    func content(for transcript: Transcript, format: ExportFormat) throws -> String {
        try validateSegments(transcript.segments)
        switch format {
        case .txt:
            return exportTXT(transcript)
        case .markdown:
            return exportMarkdown(transcript)
        case .json:
            return try exportJSON(transcript)
        case .srt:
            return exportSRT(transcript)
        case .vtt:
            return exportVTT(transcript)
        }
    }

    func write(transcript: Transcript, format: ExportFormat, to url: URL) throws {
        let text = try content(for: transcript, format: format)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.exportFailedWithReason(error)
        }
    }

    /// Validates the order, overlap, and range of subtitle segment start/end times.
    /// - Negative values, NaN, and start > end are invalid
    /// - A previous segment's end greater than the next segment's start (overlap) is invalid
    /// If anything is invalid, the export is aborted and the user is notified.
    private func validateSegments(_ segments: [TranscriptSegment]) throws {
        var previousEnd: TimeInterval?
        for segment in segments {
            guard segment.startTime.isFinite,
                  segment.endTime.isFinite,
                  segment.startTime >= 0,
                  segment.endTime >= 0 else {
                throw AppError.exportFailed(
                    NSLocalizedString("字幕の時間情報が不正です（負の値または非数値）。", comment: "Invalid subtitle timing")
                )
            }
            guard segment.endTime > segment.startTime else {
                throw AppError.exportFailed(
                    NSLocalizedString("字幕の開始時刻が終了時刻より後になっています。", comment: "Subtitle start after end")
                )
            }
            if let previousEnd, segment.startTime < previousEnd {
                throw AppError.exportFailed(
                    NSLocalizedString("字幕セグメントが重なっています。", comment: "Overlapping subtitle segments")
                )
            }
            previousEnd = segment.endTime
        }
    }

    private func exportTXT(_ transcript: Transcript) -> String {
        transcript.fullText
    }

    private func exportMarkdown(_ transcript: Transcript) -> String {
        var lines: [String] = []
        lines.append("# Transcript: \(escapeMarkdown(transcript.sourceFileName))")
        lines.append("")
        if let language = transcript.language {
            lines.append("Language: \(escapeMarkdown(language))")
            lines.append("")
        }
        lines.append("## Full Text")
        lines.append("")
        lines.append(transcript.fullText)
        lines.append("")
        lines.append("## Segments")
        lines.append("")

        for segment in transcript.segments {
            let start = formatTimestamp(segment.startTime, separator: ".")
            let end = formatTimestamp(segment.endTime, separator: ".")
            lines.append("- [\(start) --> \(end)] \(escapeMarkdown(segment.text))")
        }

        return lines.joined(separator: "\n")
    }

    /// Escapes special characters in file names and segment text
    /// so they do not break Markdown headings, lists, or links.
    private func escapeMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "#", with: "\\#")
    }
    private func exportJSON(_ transcript: Transcript) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AppError.exportFailed("Failed to encode JSON as UTF-8.")
        }
        return string
    }

    private func exportSRT(_ transcript: Transcript) -> String {
        var blocks: [String] = []
        let segments = transcript.segments.isEmpty
            ? [fallbackSegment(for: transcript)]
            : transcript.segments

        for (index, segment) in segments.enumerated() {
            let start = formatTimestamp(segment.startTime, separator: ",")
            let end = formatTimestamp(segment.endTime, separator: ",")
            blocks.append("\(index + 1)")
            blocks.append("\(start) --> \(end)")
            blocks.append(segment.text)
            blocks.append("")
        }

        return blocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exportVTT(_ transcript: Transcript) -> String {
        var lines = ["WEBVTT", ""]
        let segments = transcript.segments.isEmpty
            ? [fallbackSegment(for: transcript)]
            : transcript.segments

        for segment in segments {
            let start = formatTimestamp(segment.startTime, separator: ".")
            let end = formatTimestamp(segment.endTime, separator: ".")
            lines.append("\(start) --> \(end)")
            lines.append(segment.text)
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Subtitle fallback for when there are no segments.
    /// Instead of an invalid 00:00:00 -> 00:00:00 range, the entire text is
    /// shown as a rough 1-second range starting at 0 seconds (since the real timing is unknown).
    private func fallbackSegment(for transcript: Transcript) -> TranscriptSegment {
        TranscriptSegment(startTime: 0, endTime: 1, text: transcript.fullText)
    }

    private func formatTimestamp(_ time: TimeInterval, separator: String) -> String {
        let totalMilliseconds = max(0, Int(time * 1000))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, seconds, milliseconds)
    }
}
