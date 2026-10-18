import AVFoundation
import CryptoKit
import Foundation

struct AudioFileInfo: Sendable, Equatable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSizeBytes: Int64
    let formattedFileSize: String
}

struct AudioFileService {
    let supportedExtensions: [String]

    init(supportedExtensions: [String] = AppConfig.shared.supportedExtensions) {
        self.supportedExtensions = supportedExtensions.map { $0.lowercased() }
    }

    func validate(url: URL, preferredFileName: String? = nil) throws -> AudioFileInfo {
        let pathExt = url.pathExtension.lowercased()
        let ext: String
        if pathExt.isEmpty {
            guard let resolved = SupportedAudioTypes.resolveExtension(for: url, preferredFileName: preferredFileName),
                  supportedExtensions.contains(resolved) else {
                throw AppError.unsupportedFileExtension("unknown")
            }
            ext = resolved
        } else {
            guard supportedExtensions.contains(pathExt) else {
                throw AppError.unsupportedFileExtension(pathExt)
            }
            ext = pathExt
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return AudioFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: ext,
            fileSizeBytes: fileSize,
            formattedFileSize: Self.formatByteCount(fileSize)
        )
    }

    /// Lightly probes whether AVFoundation can actually decode the file.
    /// Helps detect corrupted files that an extension check alone would miss.
    /// - Parameter url: URL of the file to probe
    /// - Returns: true if decodable
    func probeDecodability(url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        // Synchronously access track information to check playability (lightweight probe)
        guard asset.tracks(withMediaType: .audio).first != nil || asset.isPlayable else {
            return false
        }
        return true
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Computes the file's SHA256 fingerprint.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 64 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
