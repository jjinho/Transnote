import SwiftUI

@main
struct LocalTranscriberApp: App {
    init() {
        AppDirectories.ensureDirectoriesExist()
        // Automatically clean up old temporary files and completed audio left in Imports/.
        try? AudioImportService().cleanupExpiredImports()

        // Detect configuration inconsistencies at launch (e.g., defaultModelID missing from Models) and log them.
        for error in AppConfig.shared.validationErrors {
            AppLogger.error("AppConfig validation: \(error)", logger: AppLogger.general)
        }
    }

    var body: some Scene {
        WindowGroup("Transnote") {
            MainWindowView()
        }
        .defaultSize(width: 800, height: 680)
        .commands {
            TranscriptionCommands()
        }
    }
}
