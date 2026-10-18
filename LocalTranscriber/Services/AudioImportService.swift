import Foundation

struct AudioImportService: Sendable {
    private static let copyBufferSize = 64 * 1024

    private let importsRoot: URL
    private let fileManager: FileManager
    private let maxImportFileSizeBytes: Int64

    init(
        importsRoot: URL = AppDirectories.importsDirectory,
        fileManager: FileManager = .default,
        maxImportFileSizeBytes: Int64 = AppConfig.shared.maxImportFileSizeBytes
    ) {
        self.importsRoot = importsRoot
        self.fileManager = fileManager
        self.maxImportFileSizeBytes = maxImportFileSizeBytes
    }

    func importFile(from sourceURL: URL, preferredFileName: String? = nil) throws -> URL {
        if isAlreadyImported(sourceURL) {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AppError.fileNotFound
            }
            return sourceURL
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.fileNotFound
        }

        try fileManager.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            for: resolvedFileName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        )

        // To avoid leaving partial files in Imports/, copy to a temporary file and then atomically rename it.
        // Placing the temporary file in the same directory (same volume) makes moveItem atomic.
        let temporaryURL = importsRoot.appendingPathComponent(".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")
        var importSucceeded = false
        defer {
            if !importSucceeded {
                removeFileIfExistsIfFailed(temporaryURL)
            }
        }

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Read file attributes after starting security-scoped access,
        // because in the Sandbox, fetching attributes before access starts can fail.
        // Exceeding the size limit does not fall back; it is treated as an error as-is.
        try validateFileSize(at: sourceURL)

        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        } catch {
            // If copyItem fails partway through a partial copy, debris is left at temporaryURL,
            // so delete it first and then fall back to copyFileStreaming
            removeFileIfExistsIfFailed(temporaryURL)

            if fileManager.isReadableFile(atPath: sourceURL.path) {
                try copyFileStreaming(from: sourceURL, to: temporaryURL)
            } else {
                throw AppError.fileAccessDenied
            }
        }

        // Atomically rename the temporary file to the final URL (prevents name conflicts and partial files)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        AppLogger.info(
            "Imported audio to sandbox: \(destinationURL.lastPathComponent)",
            logger: AppLogger.fileAccess
        )
        importSucceeded = true
        return destinationURL
    }

    private func validateFileSize(at url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            return
        }
        if fileSize.int64Value > maxImportFileSizeBytes {
            throw AppError.fileTooLarge
        }
    }

    private func copyFileStreaming(from sourceURL: URL, to destinationURL: URL) throws {
        guard let inputStream = InputStream(url: sourceURL) else {
            throw AppError.fileAccessDenied
        }

        fileManager.createFile(atPath: destinationURL.path, contents: nil)

        guard let outputStream = OutputStream(url: destinationURL, append: false) else {
            throw AppError.fileAccessDenied
        }

        inputStream.open()
        outputStream.open()
        defer {
            inputStream.close()
            outputStream.close()
        }

        var buffer = [UInt8](repeating: 0, count: Self.copyBufferSize)

        // hasBytesAvailable is not necessarily accurate before read,
        // so keep reading until read returns 0 (EOF).
        while true {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                removeFileIfExistsIfFailed(destinationURL)
                throw AppError.fileAccessDenied
            }
            if bytesRead == 0 {
                break
            }

            // OutputStream.write may perform partial writes,
            // so advance by the amount written and loop to write the rest.
            var writtenTotal = 0
            while writtenTotal < bytesRead {
                let remaining = Array(buffer[writtenTotal..<bytesRead])
                let bytesWritten = outputStream.write(remaining, maxLength: remaining.count)
                if bytesWritten <= 0 {
                    removeFileIfExistsIfFailed(destinationURL)
                    throw AppError.fileAccessDenied
                }
                writtenTotal += bytesWritten
            }
        }
    }

    /// Deletes the file only if it exists. A helper for removing debris at destinationURL
    /// (a partial copy from copyItem, or a file created partway through copyFileStreaming)
    /// when importFile fails. Failures are ignored.
    func removeFileIfExistsIfFailed(_ url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isAlreadyImported(_ url: URL) -> Bool {
        let sourcePath = url.standardizedFileURL.path
        let importsPath = importsRoot.standardizedFileURL.path
        guard sourcePath.hasPrefix(importsPath + "/") else {
            return false
        }
        return fileManager.fileExists(atPath: sourcePath)
    }

    private func resolvedFileName(preferredFileName: String?, sourceURL: URL) -> String {
        AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            preferredFileName: preferredFileName
        )
    }

    private func uniqueDestinationURL(for fileName: String) -> URL {
        let baseURL = importsRoot.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1

        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            let candidateURL = importsRoot.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    /// Deletes old import files under Imports/.
    /// 
    /// Targets only files older than the given number of days, so that source audio no longer needed after
    /// transcription and temporary files left over from failures do not accumulate.
    /// Temporary files (\.tmp- prefix) are targeted as well.
    func cleanupExpiredImports(maxAge: TimeInterval = 30 * 24 * 60 * 60, now: Date = Date()) throws {
        guard fileManager.fileExists(atPath: importsRoot.path) else {
            return
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: importsRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: keys)
            guard resourceValues?.isRegularFile == true else {
                continue
            }
            guard let modificationDate = resourceValues?.contentModificationDate else {
                continue
            }
            if now.timeIntervalSince(modificationDate) > maxAge {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
