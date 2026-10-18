import Foundation

final class ModelAvailabilityService: @unchecked Sendable {
    private let modelsRoot: URL
    private let fileManager: FileManager

    // In-memory index to avoid a recursive scan every time.
    // Rebuilt after a TTL (30 seconds) in case the model folder changes.
    private let cacheLock = NSLock()
    private var cachedIndex: IndexEntry?

    private struct IndexEntry {
        let timestamp: Date
        let directories: [URL]
    }

    private static let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    init(
        modelsRoot: URL = AppDirectories.modelsDirectory,
        fileManager: FileManager = .default
    ) {
        self.modelsRoot = modelsRoot
        self.fileManager = fileManager
    }

    func isDownloaded(whisperKitModelName: String) -> Bool {
        modelFolder(for: whisperKitModelName) != nil
    }

    func modelFolder(for whisperKitModelName: String) -> URL? {
        guard fileManager.fileExists(atPath: modelsRoot.path) else { return nil }

        var bestMatch: URL?
        var bestScore = -1
        var candidateCount = 0

        for url in variantDirectories(named: whisperKitModelName) {
            guard hasRequiredModelFilesDirectly(in: url) else { continue }

            let score = matchScore(for: url, whisperKitModelName: whisperKitModelName)
            if score > bestScore {
                bestScore = score
                bestMatch = url
                candidateCount = 1
            } else if score == bestScore, let current = bestMatch {
                candidateCount += 1
                // On tied scores, prefer the most recently modified; for identical times, decide deterministically by name, then path, ascending
                if isPreferredOver(url, current: current) {
                    bestMatch = url
                }
            }
        }

        if let bestMatch, candidateCount > 1 {
            AppLogger.info(
                "Found multiple model folders; selected '\(bestMatch.lastPathComponent)' out of \(candidateCount) candidates (score: \(bestScore))"
            )
        }

        return bestMatch
    }

    /// Recursively enumerates directories matching the variant name (does not verify file existence or size).
    /// Used during download-failure cleanup to identify folders that existed before the download.
    /// - Parameter includingHidden: When `true`, also enumerates HuggingFace's `.cache` and similar.
    ///   Model selection excludes incomplete staging areas; failure cleanup includes them so leftovers can be removed.
    func variantDirectories(named whisperKitModelName: String, includingHidden: Bool = false) -> [URL] {
        // Recursively scan only the first time or after the TTL expires; use the cache afterward.
        // includingHidden is needed for download-failure cleanup,
        // so in that case the cache is ignored and the scan is done directly.
        let allDirectories: [URL]
        if includingHidden {
            allDirectories = scanVariantDirectories(includingHidden: true)
        } else {
            cacheLock.lock()
            let cached = cachedIndex
            cacheLock.unlock()
            if let cached, Date().timeIntervalSince(cached.timestamp) < 30 {
                allDirectories = cached.directories
            } else {
                allDirectories = scanVariantDirectories(includingHidden: false)
                cacheLock.lock()
                cachedIndex = IndexEntry(timestamp: Date(), directories: allDirectories)
                cacheLock.unlock()
            }
        }

        return allDirectories.filter { matchesVariant(url: $0, whisperKitModelName: whisperKitModelName) }
    }

    /// Recursively scans under the model root and returns candidate variant directories (for caching).
    private func scanVariantDirectories(includingHidden: Bool) -> [URL] {
        guard fileManager.fileExists(atPath: modelsRoot.path) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            return []
        }

        return enumerator.compactMap { object in
            guard let url = object as? URL else { return nil }
            guard isDirectory(url) else { return nil }
            if !includingHidden, hasHiddenPathComponent(url) { return nil }
            return url
        }
    }

    func validateModelFolder(_ folder: URL) -> Bool {
        hasRequiredModelFilesDirectly(in: folder)
    }

    /// Returns the disk usage in bytes of the given model. 0 if not downloaded.
    func diskUsage(whisperKitModelName: String) -> Int64 {
        guard let folder = modelFolder(for: whisperKitModelName) else { return 0 }
        return directorySize(in: folder)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    /// Determines whether a path is a hidden path in HuggingFace's download staging area (.cache, etc.).
    private func hasHiddenPathComponent(_ url: URL) -> Bool {
        url.pathComponents.contains { $0.hasPrefix(".") }
    }

    private func matchesVariant(url: URL, whisperKitModelName: String) -> Bool {
        let folderName = url.lastPathComponent.lowercased()
        let variant = whisperKitModelName.lowercased()

        if folderName == variant || folderName == "openai_whisper-\(variant)" {
            return true
        }

        return folderName.hasSuffix("-\(variant)")
    }

    private func matchScore(for url: URL, whisperKitModelName: String) -> Int {
        let folderName = url.lastPathComponent.lowercased()
        let variant = whisperKitModelName.lowercased()

        if folderName == variant {
            return 100
        }

        if folderName == "openai_whisper-\(variant)" {
            return 90
        }

        if folderName.hasSuffix("-\(variant)") {
            return 80
        }

        return 0
    }

    /// Compares candidates with tied scores. Prefers the most recently modified; for identical times, compares by name,
    /// and for identical names, by normalized path ascending, so the result is deterministic.
    /// If the modification date cannot be obtained, still compares by name, then path, independent of enumeration order.
    private func isPreferredOver(_ newCandidate: URL, current: URL) -> Bool {
        let newDate = modificationDate(of: newCandidate)
        let currentDate = modificationDate(of: current)

        if let newDate, let currentDate, newDate != currentDate {
            return newDate > currentDate
        }

        let newName = newCandidate.lastPathComponent
        let currentName = current.lastPathComponent
        if newName != currentName {
            return newName < currentName
        }

        return newCandidate.standardizedFileURL.path < current.standardizedFileURL.path
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// WhisperKit references the .mlmodelc files directly under modelFolder, so recursive search is not used.
    /// Files left at 0 bytes by a failed download are "incomplete" and are not considered downloaded.
    private func hasRequiredModelFilesDirectly(in folder: URL) -> Bool {
        Self.requiredModelNames.allSatisfy { name in
            let compiled = folder.appendingPathComponent("\(name).mlmodelc")
            let package = folder.appendingPathComponent("\(name).mlpackage")
            return isValidModelFile(at: compiled)
                || isValidModelFile(at: package)
        }
    }

    /// Returns whether the model file exists and has content (i.e., was downloaded successfully).
    /// - `.mlmodelc` / `.mlpackage` can be either a file or a directory (bundle).
    /// - A file is incomplete if it is 0 bytes. A directory's inode size is always greater than 0,
    ///   so also confirm it has at least one child entry.
    private func isValidModelFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            // A compiled model (.mlmodelc) has coremldata.bin or model.mil;
            // a .mlpackage has Data/com.apple.CoreML/Model.mil. A merely empty directory is not enough.
            let coreMLBinary = url.appendingPathComponent("coremldata.bin")
            let milFile = url.appendingPathComponent("model.mil")
            let packageMil = url.appendingPathComponent("Data").appendingPathComponent("com.apple.CoreML").appendingPathComponent("Model.mil")
            let hasCoreMLPayload = fileManager.fileExists(atPath: coreMLBinary.path)
                || fileManager.fileExists(atPath: milFile.path)
                || fileManager.fileExists(atPath: packageMil.path)

            // Typical models on the web are mostly .mlmodelc rather than .mlpackage, but in either case
            // require real content (128 KB or more).
            guard hasCoreMLPayload || directorySize(in: url) > 128 * 1024 else {
                return false
            }
            return true
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        let size = attributes[.size] as? NSNumber
        return (size?.intValue ?? -1) > 0
    }

    /// Returns the total size in bytes under the directory (helper for integrity verification).
    private func directorySize(in directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else { continue }
            total += Int64((try? url.resourceValues(forKeys: keys))?.fileSize ?? 0)
        }
        return total
    }
}
