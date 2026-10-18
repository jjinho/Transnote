import AppKit
import Foundation

@MainActor
final class UpdateCheckViewModel: ObservableObject {
    @Published private(set) var updateOffer: UpdateOffer?

    private let updateChecker: any UpdateChecking
    private let settings: AppSettings
    private var hasCheckedOnLaunch = false

    init(updateChecker: any UpdateChecking = UpdateCheckService(), settings: AppSettings = .shared) {
        self.updateChecker = updateChecker
        self.settings = settings
    }

    func checkOnLaunch() {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true
        guard settings.updateCheckEnabled else { return }

        Task {
            let offer = await updateChecker.checkForUpdate()
            updateOffer = offer
        }
    }

    /// Manual check from the menu. Always checks, regardless of the launch flag.
    func checkNow() {
        Task {
            let offer = await updateChecker.checkForUpdate()
            updateOffer = offer
        }
    }

    func dismissUpdateOffer() {
        updateOffer = nil
    }

    func openDownloadPage() {
        guard let downloadURL = updateOffer?.downloadURL else { return }
        NSWorkspace.shared.open(downloadURL)
        updateOffer = nil
    }
}
