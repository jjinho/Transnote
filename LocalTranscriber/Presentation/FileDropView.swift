import SwiftUI

struct FileDropView: View {
    let supportedExtensions: [String]
    let selectedFile: AudioFileInfo?
    let onFileSelected: (URL, String?) -> Void
    let audioImportService: AudioImportService
    var isBusy: Bool = false

    @State private var isTargeted = false
    @State private var isHovered = false
    @State private var dropErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat = DesignTokens.Corner.card

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.controlSpacing) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: DesignTokens.Icon.hero))
                .foregroundStyle(.secondary)

            if let selectedFile {
                Text(selectedFile.fileName)
                    .font(.headline)
                Text("\(selectedFile.fileExtension.uppercased()) · \(selectedFile.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("音声ファイルをここにドロップ")
                    .font(.headline)
                Text("対応形式: \(supportedExtensions.map { $0.uppercased() }.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("ファイルを開く…") {
                openFilePanel()
            }
            .disabled(isBusy)
            .keyboardShortcut("o", modifiers: [.command])
            .help("音声ファイルを開く（⌘O）")
            .accessibilityLabel("音声ファイルを開く")
            .accessibilityHint("ファイルを開くダイアログを開きます")

            if let dropErrorMessage {
                HStack(spacing: DesignTokens.Spacing.compactSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Text(dropErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Button {
                        self.dropErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.Colors.warning.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("エラーを閉じる")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            minHeight: DesignTokens.Layout.dropZoneMinHeight,
            maxHeight: DesignTokens.Layout.dropZoneMaxHeight
        )
        .padding(24)
        .background(dropZoneSurface)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: acceptedDropTypes, isTargeted: $isTargeted) { providers in
            guard !isBusy else { return false }
            return handleDrop(providers: providers)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dropZoneAccessibilityLabel)
        .accessibilityHint(dropZoneAccessibilityHint)
    }

    private var supportedFormatsDescription: String {
        supportedExtensions.map { $0.uppercased() }.joined(separator: ", ")
    }

    private var dropZoneAccessibilityLabel: String {
        if let selectedFile {
            return String(
                format: NSLocalizedString("選択中の音声ファイル、%@", comment: "Drop zone accessibility label with selected file"),
                selectedFile.fileName
            )
        }
        return NSLocalizedString("音声ファイルのドロップゾーン", comment: "Drop zone accessibility label")
    }

    private var dropZoneAccessibilityHint: String {
        if selectedFile != nil {
            return NSLocalizedString(
                "別の音声ファイルをドロップまたはファイルを開くで差し替えできます",
                comment: "Drop zone accessibility hint when a file is selected"
            )
        }
        return String(
            format: NSLocalizedString(
                "対応形式は %@ です。音声ファイルをドロップするか、ファイルを開いてください",
                comment: "Drop zone accessibility hint"
            ),
            supportedFormatsDescription
        )
    }

    private var dropZoneSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(DesignTokens.Colors.opaqueSurface) : AnyShapeStyle(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(dropAccentFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(dropBorderColor, lineWidth: 1)
            }
            .shadow(
                color: dropShadowColor,
                radius: isTargeted ? 12 : (isHovered ? 8 : 4),
                y: isTargeted ? 4 : 2
            )
    }

    private var dropAccentFill: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.08)
        }
        if isHovered {
            return DesignTokens.Colors.hoverFill(colorScheme)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.5)
    }

    private var dropBorderColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.45)
        }
        return DesignTokens.Colors.border(colorScheme)
    }

    private var dropShadowColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.18)
        }
        return DesignTokens.Colors.dropShadow(colorScheme, isHovered: isHovered)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = contentTypesForPicker()

        if panel.runModal() == .OK, let url = panel.url {
            dropErrorMessage = nil
            onFileSelected(url, nil)
        }
    }

    private var acceptedDropTypes: [UTType] {
        var types: [UTType] = [.fileURL, .audio]
        types.append(contentsOf: SupportedAudioTypes.allowedContentTypes(for: supportedExtensions))
        return Array(Set(types))
    }

    private func contentTypesForPicker() -> [UTType] {
        SupportedAudioTypes.allowedContentTypes(for: supportedExtensions)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        dropErrorMessage = nil

        // Dropping multiple files is not officially supported (currently only one file).
        // Reject it explicitly to make the expected behavior clear to the user.
        if providers.count > 1 {
            dropErrorMessage = NSLocalizedString(
                "複数ファイルのドロップには対応していません。1つの音声ファイルをドロップしてください。",
                comment: "Multiple file drop unsupported"
            )
            return false
        }

        guard let provider = providers.first else { return false }

        let suggestedName = provider.suggestedName
        let typeIdentifiers = DropImportService.preferredTypeIdentifiers(from: provider)

        loadDropItem(
            provider: provider,
            typeIdentifiers: typeIdentifiers,
            index: 0,
            suggestedName: suggestedName
        )
        return true
    }

    private func loadDropItem(
        provider: NSItemProvider,
        typeIdentifiers: [String],
        index: Int,
        suggestedName: String?
    ) {
        guard index < typeIdentifiers.count else {
            AppLogger.error("Drop import failed: unsupported dropped item", logger: AppLogger.fileAccess)
            DispatchQueue.main.async {
                self.dropErrorMessage = NSLocalizedString(
                    "対応している音声ファイルを読み込めませんでした。",
                    comment: "Dropped item could not be loaded"
                )
            }
            return
        }

        let typeIdentifier = typeIdentifiers[index]

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, error in
            guard let tempURL else {
                self.loadDropItem(
                    provider: provider,
                    typeIdentifiers: typeIdentifiers,
                    index: index + 1,
                    suggestedName: suggestedName
                )
                return
            }

            self.importDroppedRepresentation(
                tempURL: tempURL,
                suggestedName: suggestedName,
                typeIdentifiers: typeIdentifiers
            )
        }
    }

    private func importDroppedRepresentation(
        tempURL: URL,
        suggestedName: String?,
        typeIdentifiers: [String]
    ) {
        let fileName = DropImportService.resolvedFileName(
            sourceURL: tempURL,
            suggestedName: suggestedName,
            typeIdentifiers: typeIdentifiers
        )

        guard DropImportService.hasSupportedExtension(fileName, supportedExtensions: supportedExtensions) else {
            AppLogger.error("Drop import failed: unsupported extension for \(fileName)", logger: AppLogger.fileAccess)
            DispatchQueue.main.async {
                self.dropErrorMessage = ErrorMapper.userMessage(for: AppError.unsupportedFileExtension(fileName))
            }
            return
        }

        do {
            let importedURL = try audioImportService.importFile(
                from: tempURL,
                preferredFileName: fileName
            )
            DispatchQueue.main.async {
                self.dropErrorMessage = nil
                self.onFileSelected(importedURL, nil)
            }
        } catch {
            AppLogger.error("Drop import failed: \(error.localizedDescription)", logger: AppLogger.fileAccess)
            DispatchQueue.main.async {
                self.dropErrorMessage = ErrorMapper.userMessage(for: error)
            }
        }
    }
}

import UniformTypeIdentifiers
