import Foundation

struct TranscriptionProgressDisplay: Equatable {
    enum ProgressStyle: Equatable {
        case hidden
        case indeterminate
        case determinate
    }

    let phase: TranscriptionProgressPhase
    let style: ProgressStyle
    let fraction: Double?
    let primaryLabel: String
    let detailLabel: String?

    var accessibilityLabel: String {
        if let modelName = detailLabel?.components(separatedBy: " · ").first, !modelName.isEmpty {
            return String(
                format: NSLocalizedString("%@、%@", comment: "Progress label and model name"),
                primaryLabel,
                modelName
            )
        }
        return primaryLabel
    }

    var accessibilityValue: String {
        switch style {
        case .determinate:
            let percent = Int((fraction ?? 0) * 100)
            return String(
                format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
                percent
            )
        case .indeterminate:
            return NSLocalizedString("進行中", comment: "Accessible indeterminate progress value")
        case .hidden:
            return ""
        }
    }

    static func from(update: TranscriptionProgressUpdate) -> TranscriptionProgressDisplay {
        let primaryLabel = update.phase.localizedDisplayName
        let detailLabel = makeDetailLabel(for: update)

        let style: ProgressStyle
        let fraction: Double?

        switch update.phase {
        case .downloadingModel:
            style = .determinate
            fraction = min(1.0, max(0.0, update.fraction))
        case .transcribing:
            if update.fraction > 0 {
                style = .determinate
                fraction = min(1.0, max(0.0, update.fraction))
            } else {
                // Show indeterminate progress when actual progress is unknown
                style = .indeterminate
                fraction = nil
            }
        case .loadingModel, .convertingAudio, .initializing:
            style = .indeterminate
            fraction = nil
        case .finished:
            style = .hidden
            fraction = 1.0
        }

        return TranscriptionProgressDisplay(
            phase: update.phase,
            style: style,
            fraction: fraction,
            primaryLabel: primaryLabel,
            detailLabel: detailLabel
        )
    }

    static func idle() -> TranscriptionProgressDisplay {
        TranscriptionProgressDisplay(
            phase: .finished,
            style: .hidden,
            fraction: nil,
            primaryLabel: NSLocalizedString("待機中", comment: "Idle state label"),
            detailLabel: nil
        )
    }

    static func done() -> TranscriptionProgressDisplay {
        TranscriptionProgressDisplay(
            phase: .finished,
            style: .hidden,
            fraction: 1.0,
            primaryLabel: NSLocalizedString("完了", comment: "Done state label"),
            detailLabel: nil
        )
    }

    private static func makeDetailLabel(for update: TranscriptionProgressUpdate) -> String? {
        switch update.phase {
        case .downloadingModel:
            var detail = ""
            if let modelName = update.modelDisplayName {
                detail = modelName
            }
            if let resume = update.resumeState {
                detail = detail.isEmpty ? resume : "\(detail) · \(resume)"
            }
            if let completed = update.completedUnitCount,
               let total = update.totalUnitCount,
               total > 0 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let completedText = formatter.string(fromByteCount: completed)
                let totalText = formatter.string(fromByteCount: total)
                return detail.isEmpty
                    ? "\(completedText) / \(totalText)"
                    : "\(detail) · \(completedText) / \(totalText)"
            }
            let percent = Int(update.fraction * 100)
            return detail.isEmpty ? "\(percent)%" : "\(detail) · \(percent)%"

        case .loadingModel:
            let guidance = NSLocalizedString(
                "初回のモデル読み込みは時間がかかることがあります",
                comment: "Loading model indeterminate progress guidance"
            )
            if let modelName = update.modelDisplayName {
                return "\(modelName) · \(guidance)"
            }
            return guidance

        case .transcribing:
            let percent = Int(update.fraction * 100)
            if let partialText = update.partialText,
               TranscriptTextSanitizer.presentableText(from: partialText) != nil {
                let partialGuidance = NSLocalizedString("途中結果を表示中", comment: "Partial transcription guidance")
                return percent > 0 ? "\(partialGuidance) · \(percent)%" : partialGuidance
            }
            return percent > 0 ? "\(percent)%" : nil

        case .convertingAudio:
            // At this stage WhisperKit is actually loading the audio file and running model preprocessing (MelSpectrogram, etc.).
            // The on-screen wording should make that clear.
            if let modelName = update.modelDisplayName {
                return "\(modelName) · " + NSLocalizedString(
                    "音声を読み込んでいます（モデルの前処理）",
                    comment: "Converting audio progress guidance"
                )
            }
            return NSLocalizedString(
                "音声を読み込んでいます（モデルの前処理）",
                comment: "Converting audio progress guidance"
            )

        case .initializing:
            return NSLocalizedString(
                "文字起こしの準備をしています。",
                comment: "Initializing indeterminate progress guidance"
            )

        case .finished:
            return update.modelDisplayName
        }
    }
}
