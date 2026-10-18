import SwiftUI

struct TranscriptEditorView: View {
    @Binding var text: String
    let isEditable: Bool
    let isBusy: Bool
    let segments: [TranscriptSegment]?
    let playingSegmentID: UUID?
    let playbackPositionText: String
    @Binding var isEditing: Bool
    let onSegmentTap: (TranscriptSegment) -> Void
    let onSegmentTextChange: (UUID, String) -> Void
    let onCopy: () -> Void
    let onSegmentPause: () -> Void
    let onSegmentResume: () -> Void
    let isSegmentPaused: Bool
    let onStopPlayback: () -> Void
    var needsModelDownload: Bool = false
    var onTranscriptTextChange: ((String) -> Void)? = nil

    @FocusState private var isEditorFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var hasPlayableSegments: Bool {
        guard let segments else { return false }
        return !segments.isEmpty
    }

    private var isShowingEmptyPlaceholder: Bool {
        text.isEmpty && !isBusy && !isEditable
    }

    private let cornerRadius: CGFloat = DesignTokens.Corner.card
    private let cardPadding: CGFloat = DesignTokens.Card.padding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, DesignTokens.Spacing.controlSpacing)

            Divider()
                .overlay(DesignTokens.Colors.border(colorScheme))
                .padding(.bottom, DesignTokens.Spacing.controlSpacing)

            editorContent
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardSurface)
        .opacity(isShowingEmptyPlaceholder ? 0.72 : 1)
        .accessibilityElement(children: .contain)
        .onChange(of: isEditing) { isEditing in
            if isEditing {
                isEditorFocused = true
            }
        }
        .onChange(of: isEditable) { editable in
            if editable && !hasPlayableSegments {
                isEditing = true
            }
        }
        .onChange(of: hasPlayableSegments) { hasSegments in
            if isEditable && !hasSegments {
                isEditing = true
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        Group {
            if isEditable {
                if isEditing {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.compactSpacing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
                        )
                        .focused($isEditorFocused)
                        .onChange(of: text) { newValue in
                            onTranscriptTextChange?(newValue)
                        }
                } else if hasPlayableSegments, let segments {
                    segmentPlaybackView(segments: segments)
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                        readOnlyTextView
                        if !text.isEmpty {
                            Text("タイムスタンプ情報がないため、クリック再生は利用できません。編集モードでテキストを修正できます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                readOnlyTextView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
            }
    }

    private var header: some View {
        HStack {
            Text("文字起こし結果")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("文字起こし")
            if isBusy, !text.isEmpty {
                Text(
                    NSLocalizedString("途中結果", comment: "Partial transcription result badge")
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.16))
                )
                .foregroundStyle(.orange)
                .accessibilityLabel(
                    NSLocalizedString("途中結果", comment: "Partial transcription result badge")
                )
            }
            Spacer()
            if isEditable, !text.isEmpty, hasPlayableSegments {
                Picker("表示", selection: $isEditing) {
                    Text(
                        NSLocalizedString("セグメント", comment: "Segment playback mode picker label")
                    ).tag(false)
                    Text("編集").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 120)
                .accessibilityLabel("表示モード")
                .accessibilityHint(
                    NSLocalizedString(
                        "セグメント再生モードと編集モードを切り替えます",
                        comment: "Segment playback and edit mode picker hint"
                    )
                )
            }
            if isEditing {
                copyButton
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("文字起こし結果全体をコピー（⌘⇧C）")
            } else {
                copyButton
                    .keyboardShortcut("c", modifiers: [.command])
                    .help("文字起こし結果をコピー（⌘C）")
            }
        }
    }

    private var copyButton: some View {
        Button("コピー") {
            onCopy()
        }
        .disabled(text.isEmpty)
        .accessibilityLabel("文字起こしをコピー")
        .accessibilityHint("クリップボードに文字起こし結果全体をコピーします")
    }

    private var readOnlyTextView: some View {
        ScrollView {
            if text.isEmpty {
                EmptyStateView(message: emptyStateMessage, isBusy: isBusy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.compactSpacing)
            } else {
                Text(text)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.compactSpacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
        )
    }

    private var emptyStateMessage: String {
        if isBusy {
            return NSLocalizedString("処理が完了するまでお待ちください", comment: "Wait for processing empty state")
        }
        if needsModelDownload {
            return NSLocalizedString(
                "初回はモデルのダウンロードが必要です。音声ファイルを選択・ドロップ後、「文字起こしを開始」してください。",
                comment: "Empty state prompting model download"
            )
        }
        return NSLocalizedString("音声ファイルをドロップまたは選択して、文字起こしを開始してください", comment: "Empty state prompting file selection")
    }

    private func segmentPlaybackView(segments: [TranscriptSegment]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(segments) { segment in
                    SegmentPlaybackRow(
                        segment: segment,
                        isPlaying: playingSegmentID == segment.id,
                        playbackPositionText: playbackPositionText,
                        isPaused: isSegmentPaused,
                        onTap: { onSegmentTap(segment) },
                        onPause: onSegmentPause,
                        onResume: onSegmentResume,
                        onStop: onStopPlayback,
                        onTextChange: { newText in onSegmentTextChange(segment.id, newText) }
                    )
                }
            }
            .padding(DesignTokens.Spacing.compactSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
        )
    }
}

private struct EmptyStateView: View {
    let message: String
    let isBusy: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.compactSpacing) {
            Image(systemName: isBusy ? "waveform" : "doc.text.magnifyingglass")
                .font(.system(size: DesignTokens.Icon.hero))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.sectionSpacing)
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentPlaybackRow: View {
    let segment: TranscriptSegment
    let isPlaying: Bool
    let playbackPositionText: String
    let isPaused: Bool
    let onTap: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onTextChange: (String) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(isPlaying ? Color.accentColor : .secondary)
                    .frame(width: DesignTokens.Icon.compact)
                    .symbolEffect(.variableColor, isActive: isPlaying && !reduceMotion)

                if isPlaying {
                    Button(isPaused ? "再開" : "一時停止") {
                        if isPaused {
                            onResume()
                        } else {
                            onPause()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .accessibilityLabel(isPaused ? "再生を再開" : "再生を一時停止")
                }

                Text(segment.formattedStartTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)

                if isPlaying, !playbackPositionText.isEmpty {
                    Text("残り \(playbackPositionText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("残り時間 \(playbackPositionText)")
                }

                TextField("", text: Binding(
                    get: { segment.text },
                    set: { onTextChange($0) }
                ))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                if let lowConfidenceSummary {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(lowConfidenceSummary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Corner.segment)
                    .fill(backgroundColor)
            }
            .overlay(alignment: .leading) {
                if isPlaying {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityLabel(
            lowConfidenceSummary.map { Text("\(segment.accessibilityStartTimestamp)、\(segment.text)、\($0)") }
                ?? Text("\(segment.accessibilityStartTimestamp)、\(segment.text)")
        )
        .accessibilityValue(isPlaying ? "再生中" : "停止中")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("スワイプアップまたはダウンで再生・停止できます")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onTap()
            case .decrement:
                onStop()
            @unknown default:
                break
            }
        }
    }

    /// Lists the words the model was unsure about with their scores, e.g. "Low-confidence words: Hollis 42%, crate 48%".
    private var lowConfidenceSummary: String? {
        let words = segment.lowConfidenceWords
        guard !words.isEmpty else { return nil }
        let list = words
            .map { "\($0.text) \($0.probability.formatted(.percent.precision(.fractionLength(0))))" }
            .joined(separator: ", ")
        return String(
            format: NSLocalizedString("信頼度の低い単語: %@", comment: "Tooltip listing low-confidence words with their scores"),
            list
        )
    }

    private var backgroundColor: Color {
        if isPlaying {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.secondary.opacity(0.08)
        }
        return Color.clear
    }
}
