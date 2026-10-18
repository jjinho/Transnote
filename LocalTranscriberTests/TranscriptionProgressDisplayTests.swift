import XCTest
@testable import LocalTranscriber

final class TranscriptionProgressDisplayTests: XCTestCase {
    func testDownloadingModelShowsPercentDetail() {
        // Given: downloading at 45%
        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.45,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.fraction, 0.45)
        XCTAssertEqual(display.primaryLabel, TranscriptionProgressPhase.downloadingModel.localizedDisplayName)
        XCTAssertEqual(display.detailLabel, "Base · 45%")
    }

    func testDownloadingModelShowsByteDetailWhenAvailable() {
        // Given: Progress with byte progress
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 64

        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.64,
            progress: progress,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertTrue(display.detailLabel?.contains("Base · ") == true)
        XCTAssertTrue(display.detailLabel?.contains("/") == true)
    }

    func testLoadingModelUsesIndeterminateStyle() {
        // Given: loading the model
        let update = TranscriptionProgressUpdate.make(
            phase: .loadingModel,
            fraction: 0,
            modelDisplayName: "Small"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .indeterminate)
        XCTAssertNil(display.fraction)
        XCTAssertTrue(display.detailLabel?.contains("Small") == true)
        XCTAssertTrue(
            display.detailLabel?.contains(
                L("初回のモデル読み込みは時間がかかることがあります", comment: "Loading model indeterminate progress guidance")
            ) == true
        )
    }

    func testTranscribingUsesDeterminateStyle() {
        // Given: transcribing at 32%
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 0.32,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.detailLabel, "32%")
    }

    func testLoadingModelIncludesGuidanceDetail() {
        let update = TranscriptionProgressUpdate.make(
            phase: .loadingModel,
            fraction: 0,
            modelDisplayName: "Base"
        )

        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertEqual(display.style, .indeterminate)
        XCTAssertTrue(display.detailLabel?.contains("Base") == true)
        XCTAssertTrue(
            display.detailLabel?.contains(
                L("初回のモデル読み込みは時間がかかることがあります", comment: "Loading model indeterminate progress guidance")
            ) == true
        )
    }

    func testTranscribingWithPartialTextIncludesPartialGuidance() {
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 0.5,
            partialText: "Hello"
        )

        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertTrue(
            display.detailLabel?.contains(L("途中結果を表示中", comment: "Partial transcription guidance")) == true
        )
        XCTAssertTrue(display.detailLabel?.contains("50%") == true)
    }

    func testIdleDisplayUsesWaitingLabel() {
        let display = TranscriptionProgressDisplay.idle()

        XCTAssertEqual(
            display.primaryLabel,
            NSLocalizedString("待機中", comment: "Idle state label")
        )
    }

    func testAccessibilityLabelsForDownloadProgress() {
        // Given
        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.45,
            modelDisplayName: "Base"
        )
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        let expectedLabel = String(
            format: NSLocalizedString("%@、%@", comment: "Progress label and model name"),
            TranscriptionProgressPhase.downloadingModel.localizedDisplayName,
            "Base"
        )
        let expectedValue = String(
            format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
            45
        )
        XCTAssertEqual(display.accessibilityLabel, expectedLabel)
        XCTAssertEqual(display.accessibilityValue, expectedValue)
    }
}
