import XCTest
@testable import LocalTranscriber

/// Investigative probe (not a regression test).
/// It only logs how model folders already present locally are resolved;
/// it does not touch the network or downloads and never fails (always passes).
final class ModelResolveProbeTests: XCTestCase {
    func testProbeModelFolders() {
        let service = ModelAvailabilityService(modelsRoot: AppDirectories.modelsDirectory)
        let variants = ["tiny", "large-v3-v20240930_turbo", "large-v3-v20240930_626MB", "base"]
        for variant in variants {
            let folder = service.modelFolder(for: variant)
            print("=== PROBE \(variant): \(folder?.path ?? "NIL")")
            if let folder {
                print("=== PROBE valid: \(service.validateModelFolder(folder))")
            }
        }
        let allDirs = service.variantDirectories(named: "large-v3-v20240930_turbo")
        print("=== PROBE variantDirs count: \(allDirs.count)")
        for d in allDirs {
            print("=== PROBE dir: \(d.path)")
        }
        // No assertions, since this is investigative (does not fail CI when no model is present)
        XCTAssertTrue(true)
    }
}
