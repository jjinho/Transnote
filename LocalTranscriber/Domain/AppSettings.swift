import Foundation

struct ModelOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let whisperKitModelName: String

    /// Download size in bytes. nil if not set.
    let downloadSizeBytes: Int64?
    let license: String?
    let distributionSource: String?
    let modelVersion: String?

    init(
        id: String,
        displayName: String,
        whisperKitModelName: String,
        downloadSizeBytes: Int64? = nil,
        license: String? = nil,
        distributionSource: String? = nil,
        modelVersion: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.whisperKitModelName = whisperKitModelName
        self.downloadSizeBytes = downloadSizeBytes
        self.license = license
        self.distributionSource = distributionSource
        self.modelVersion = modelVersion
    }

    /// Localized display name from Localizable.xcstrings.
    var localizedDisplayName: String {
        NSLocalizedString("model.\(id)", comment: "Model display name")
    }
}

struct LanguageOption: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String

    /// Localized display name from Localizable.xcstrings.
    var localizedDisplayName: String {
        NSLocalizedString("language.\(id)", comment: "Language display name")
    }
}

/// Abstraction of AppSettings referenced by ViewModels and others. Made a protocol for testing and DI.
@MainActor
protocol AppSettingsProviding: AnyObject, ObservableObject {
    var selectedModelID: String { get set }
    var selectedLanguageID: String { get set }
    var models: [ModelOption] { get }
    var languages: [LanguageOption] { get }
    var supportedExtensions: [String] { get }
    var selectedModel: ModelOption? { get }
    var selectedLanguage: LanguageOption? { get }
    var vadEnabled: Bool { get set }
    func persist()
}

@MainActor
final class AppSettings: ObservableObject, AppSettingsProviding {
    static let shared = AppSettings()

    @Published var selectedModelID: String
    @Published var selectedLanguageID: String
    @Published var updateCheckEnabled: Bool
    @Published var defaultExportFormat: ExportFormat
    @Published var vadEnabled: Bool

    let models: [ModelOption]
    let languages: [LanguageOption]
    let supportedExtensions: [String]

    private let defaults = UserDefaults.standard
    private let modelKey = "selectedModelID"
    private let languageKey = "selectedLanguageID"
    private let updateCheckKey = "updateCheckEnabled"
    private let defaultExportFormatKey = "defaultExportFormat"
    private let vadKey = "vadEnabled"

    private init() {
        let config = AppConfig.shared
        models = config.models
        languages = config.languages
        supportedExtensions = config.supportedExtensions

        let defaultModel = config.defaultModelID
        let defaultLanguage = config.defaultLanguageID

        selectedModelID = defaults.string(forKey: modelKey) ?? defaultModel
        selectedLanguageID = defaults.string(forKey: languageKey) ?? defaultLanguage
        updateCheckEnabled = defaults.object(forKey: updateCheckKey) as? Bool ?? config.updateCheckEnabled
        if let raw = defaults.string(forKey: defaultExportFormatKey),
           let format = ExportFormat(rawValue: raw) {
            defaultExportFormat = format
        } else {
            defaultExportFormat = .txt
        }
        vadEnabled = defaults.object(forKey: vadKey) as? Bool ?? false

        if !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = defaultModel
        }
        if !languages.contains(where: { $0.id == selectedLanguageID }) {
            selectedLanguageID = defaultLanguage
        }
    }

    var selectedModel: ModelOption? {
        models.first { $0.id == selectedModelID }
    }

    /// Recommended model ID based on RAM and CPU core count.
    /// - 16 GB or more: small
    /// - 8 GB or more: base
    /// - Otherwise: tiny
    var recommendedModelID: String {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let cores = ProcessInfo.processInfo.processorCount
        if memoryGB >= 16 || cores >= 12 {
            return "small"
        }
        if memoryGB >= 8 {
            return "base"
        }
        return "tiny"
    }

    var recommendedModel: ModelOption? {
        models.first { $0.id == recommendedModelID }
    }

    var selectedLanguage: LanguageOption? {
        languages.first { $0.id == selectedLanguageID }
    }

    func persist() {
        defaults.set(selectedModelID, forKey: modelKey)
        defaults.set(selectedLanguageID, forKey: languageKey)
        defaults.set(updateCheckEnabled, forKey: updateCheckKey)
        defaults.set(defaultExportFormat.rawValue, forKey: defaultExportFormatKey)
        defaults.set(vadEnabled, forKey: vadKey)
    }
}

struct AppConfig {
    static let shared = AppConfig()

    let supportedExtensions: [String]
    let defaultModelID: String
    let defaultLanguageID: String
    let modelsDirectoryName: String
    let models: [ModelOption]
    let languages: [LanguageOption]
    let updateCheckEnabled: Bool
    let expectedGitHubRepository: String
    let githubReleasesAPIURL: URL
    let updateDownloadFallbackURL: URL
    let updateDMGAssetName: String
    let allowedUpdateDownloadHosts: [String]
    let maxImportFileSizeBytes: Int64

    /// Validation result for explicitly detecting configuration inconsistencies at launch.
    /// If non-empty, it is logged when LocalTranscriberApp launches.
    var validationErrors: [String] {
        var errors: [String] = []
        if defaultModelID.isEmpty {
            errors.append("defaultModelID is empty")
        } else if !models.contains(where: { $0.id == defaultModelID }) {
            errors.append("defaultModelID '\(defaultModelID)' is not present in Models")
        }
        if defaultLanguageID.isEmpty {
            errors.append("defaultLanguageID is empty")
        } else if !languages.contains(where: { $0.id == defaultLanguageID }) {
            errors.append("defaultLanguageID '\(defaultLanguageID)' is not present in Languages")
        }
        if supportedExtensions.isEmpty {
            errors.append("supportedExtensions is empty")
        }
        return errors
    }

    init(bundle: Bundle = .main) {
        let data: [String: Any]
        if let bundledURL = bundle.url(forResource: "Defaults", withExtension: "plist"),
           let loaded = NSDictionary(contentsOf: bundledURL) as? [String: Any] {
            data = loaded
        } else {
            #if DEBUG
            let developmentPlistURL = bundle.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Config/Defaults.plist")
            if let loaded = NSDictionary(contentsOf: developmentPlistURL) as? [String: Any] {
                data = loaded
            } else {
                data = [:]
            }
            #else
            data = [:]
            #endif
        }

        supportedExtensions = data["SupportedAudioExtensions"] as? [String] ?? ["wav", "mp3", "m4a", "flac"]
        defaultModelID = data["DefaultModelID"] as? String ?? "base"
        defaultLanguageID = data["DefaultLanguage"] as? String ?? "auto"
        modelsDirectoryName = data["ModelsDirectoryName"] as? String ?? "Models"

        models = Self.parseModels(from: data["Models"] as? [[String: Any]] ?? [])
        languages = Self.parseLanguages(from: data["Languages"] as? [[String: Any]] ?? [])

        updateCheckEnabled = data["UpdateCheckEnabled"] as? Bool ?? true
        expectedGitHubRepository = data["ExpectedGitHubRepository"] as? String ?? "T3pp31/Transnote"
        githubReleasesAPIURL = Self.url(
            from: data["GitHubReleasesAPIURL"] as? String,
            fallback: "https://api.github.com/repos/T3pp31/Transnote/releases/latest"
        )
        updateDownloadFallbackURL = Self.url(
            from: data["UpdateDownloadFallbackURL"] as? String,
            fallback: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg"
        )
        updateDMGAssetName = data["UpdateDMGAssetName"] as? String ?? "Transnote.dmg"
        allowedUpdateDownloadHosts = data["AllowedUpdateDownloadHosts"] as? [String]
            ?? ["github.com", "objects.githubusercontent.com"]
        maxImportFileSizeBytes = Self.int64(from: data["MaxImportFileSizeBytes"], fallback: 524_288_000)
    }

    init(
        supportedExtensions: [String],
        defaultModelID: String,
        defaultLanguageID: String,
        modelsDirectoryName: String,
        models: [ModelOption],
        languages: [LanguageOption],
        updateCheckEnabled: Bool,
        expectedGitHubRepository: String = "T3pp31/Transnote",
        githubReleasesAPIURL: URL,
        updateDownloadFallbackURL: URL,
        updateDMGAssetName: String,
        allowedUpdateDownloadHosts: [String] = ["github.com", "objects.githubusercontent.com"],
        maxImportFileSizeBytes: Int64 = 524_288_000
    ) {
        self.supportedExtensions = supportedExtensions
        self.defaultModelID = defaultModelID
        self.defaultLanguageID = defaultLanguageID
        self.modelsDirectoryName = modelsDirectoryName
        self.models = models
        self.languages = languages
        self.updateCheckEnabled = updateCheckEnabled
        self.expectedGitHubRepository = expectedGitHubRepository
        self.githubReleasesAPIURL = githubReleasesAPIURL
        self.updateDownloadFallbackURL = updateDownloadFallbackURL
        self.updateDMGAssetName = updateDMGAssetName
        self.allowedUpdateDownloadHosts = allowedUpdateDownloadHosts
        self.maxImportFileSizeBytes = maxImportFileSizeBytes
    }


    private static func int64(from value: Any?, fallback: Int64) -> Int64 {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return fallback
    }

    private static func url(from string: String?, fallback: String) -> URL {
        if let string, let url = URL(string: string) {
            return url
        }
        return URL(string: fallback)!
    }

    private static func parseModels(from raw: [[String: Any]]) -> [ModelOption] {
        raw.compactMap { item in
            guard let id = item["id"] as? String,
                  let displayName = item["displayName"] as? String,
                  let whisperKitModelName = item["whisperKitModelName"] as? String else {
                return nil
            }
            let size = (item["downloadSizeBytes"] as? NSNumber)?.int64Value
            let license = item["license"] as? String
            let source = item["distributionSource"] as? String
            let version = item["modelVersion"] as? String
            return ModelOption(
                id: id,
                displayName: displayName,
                whisperKitModelName: whisperKitModelName,
                downloadSizeBytes: size,
                license: license,
                distributionSource: source,
                modelVersion: version
            )
        }
    }

    private static func parseLanguages(from raw: [[String: Any]]) -> [LanguageOption] {
        raw.compactMap { item in
            guard let id = item["id"] as? String,
                  let displayName = item["displayName"] as? String else {
                return nil
            }
            return LanguageOption(id: id, displayName: displayName)
        }
    }
}
