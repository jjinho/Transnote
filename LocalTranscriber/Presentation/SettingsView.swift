import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    let isBusy: Bool
    let canDownloadSelectedModel: Bool
    let isModelDownloaded: (ModelOption) -> Bool
    let onDownloadSelectedModel: () -> Void
    let onDeleteSelectedModel: () -> Void
    let onDiskUsage: (ModelOption) -> String?

    private func modelSizeSuffix(_ model: ModelOption) -> String {
        guard let bytes = model.downloadSizeBytes else { return "" }
        return String(
            format: NSLocalizedString("（%@）", comment: "Model download size suffix"),
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("設定")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("設定を閉じる")
            }
            Text("各項目を選択した時点で自動保存されます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                settingsContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("診断情報をコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppDiagnostics.summary, forType: .string)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(
            minWidth: 420,
            maxWidth: .infinity,
            minHeight: 300,
            idealHeight: DesignTokens.Layout.windowMinHeight,
            maxHeight: DesignTokens.Layout.windowMinHeight
        )
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionSpacing) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                    Text("文字起こしモデル")
                        .font(.headline)
                    Picker("モデル", selection: $settings.selectedModelID) {
                        ForEach(settings.models) { model in
                            Label(
                                model.localizedDisplayName + modelSizeSuffix(model),
                                systemImage: isModelDownloaded(model)
                                    ? "checkmark.circle"
                                    : "arrow.down.circle"
                            )
                            .tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .disabled(isBusy)
                    .onChange(of: settings.selectedModelID) { _ in
                        settings.persist()
                    }
                    Text("使用するWhisperモデルを選択します。モデルは別途ダウンロードが必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let recommended = settings.recommendedModel {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "おすすめモデル: %@",
                                    comment: "Recommended model label"
                                ),
                                recommended.displayName
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if let selected = settings.selectedModel {
                        if let license = selected.license {
                            Text("ライセンス: \(license)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let source = selected.distributionSource {
                            Text("配布元: \(source)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let version = selected.modelVersion {
                            Text("モデルバージョン: \(version)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let usage = onDiskUsage(selected) {
                            Text("使用中ディスク: \(usage)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let selectedModel = settings.selectedModel,
                       !isModelDownloaded(selectedModel) {
                        Button {
                            onDownloadSelectedModel()
                        } label: {
                            Label(
                                NSLocalizedString(
                                    "このモデルをダウンロード",
                                    comment: "Download selected model from settings"
                                ),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canDownloadSelectedModel)
                        .accessibilityHint(
                            NSLocalizedString(
                                "選択中のモデルをダウンロードします",
                                comment: "Download selected model accessibility hint"
                            )
                        )
                    }

                    if let selected = settings.selectedModel,
                       isModelDownloaded(selected) {
                        Button {
                            onDeleteSelectedModel()
                        } label: {
                            Label("このモデルを削除", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("選択中のモデルを削除")
                    }
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                    Text("文字起こし言語")
                        .font(.headline)
                    Picker("言語", selection: $settings.selectedLanguageID) {
                        ForEach(settings.languages) { language in
                            Text(language.localizedDisplayName).tag(language.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300)
                    .disabled(isBusy)
                    .onChange(of: settings.selectedLanguageID) { _ in
                        settings.persist()
                    }
                    Text("音声の言語を選択します。Autoは自動検出です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                Text("ストレージ管理")
                    .font(.headline)
                StorageRow(
                    title: "Imports",
                    directory: AppDirectories.importsDirectory,
                    icon: "tray"
                )
                StorageRow(
                    title: "Models",
                    directory: AppDirectories.modelsDirectory,
                    icon: "internaldrive"
                )
            }

            Toggle(
                isOn: $settings.updateCheckEnabled
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("アップデートを自動確認")
                    Text("起動時に最新バージョンを確認します")

                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: settings.updateCheckEnabled) { _ in
                settings.persist()
            }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
                    Text("既定のエクスポート形式")
                        .font(.headline)
                    Picker("形式", selection: $settings.defaultExportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .onChange(of: settings.defaultExportFormat) { _ in
                        settings.persist()
                    }
                    Text("エクスポートメニューの初期表示に使用します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            Toggle(
                isOn: $settings.vadEnabled
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VAD（音声区間検出）")
                    Text("無音区間の幻聴を抑制します（WhisperKit 対応モデルのみ）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: settings.vadEnabled) { _ in
                settings.persist()
            }
        }
    }
}
private struct StorageRow: View {
    let title: String
    let directory: URL
    let icon: String

    @State private var sizeText: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(sizeText ?? NSLocalizedString("計算中…", comment: "Storage size is being calculated"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("クリア") {
                AppDirectories.clearDirectory(directory)
                sizeText = "0 KB"
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sizeText == nil)
        }
        .onAppear {
            let bytes = AppDirectories.directorySize(of: directory)
            sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}
