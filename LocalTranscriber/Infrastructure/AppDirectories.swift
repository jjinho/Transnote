import Foundation

enum AppDirectories {
    static var applicationSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.appendingPathComponent("LocalTranscriber", isDirectory: true)
    }

    static var modelsDirectory: URL {
        applicationSupport.appendingPathComponent(AppConfig.shared.modelsDirectoryName, isDirectory: true)
    }

    static var exportsDirectory: URL {
        applicationSupport.appendingPathComponent("Exports", isDirectory: true)
    }

    static var importsDirectory: URL {
        applicationSupport.appendingPathComponent("Imports", isDirectory: true)
    }

    static var dropStagingDirectory: URL {
        applicationSupport.appendingPathComponent("DropStaging", isDirectory: true)
    }

    static var historyDirectory: URL {
        applicationSupport.appendingPathComponent("History", isDirectory: true)
    }

    /// Computes the total size in bytes under the given directory.
    static func directorySize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
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

    /// Deletes the files under the given directory, leaving the empty directory in place.
    static func clearDirectory(_ directory: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    static var tempTranscriptsDirectory: URL {
        applicationSupport.appendingPathComponent("TempTranscripts", isDirectory: true)
    }

    static var checkpointDirectory: URL {
        applicationSupport.appendingPathComponent("Checkpoints", isDirectory: true)
    }

    static func ensureDirectoriesExist() {
        let directories = [applicationSupport, modelsDirectory, exportsDirectory, importsDirectory, dropStagingDirectory, historyDirectory, tempTranscriptsDirectory, checkpointDirectory]
        for directory in directories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
