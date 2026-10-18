import XCTest
import WhisperKit
@testable import LocalTranscriber

final class WhisperKitTranscriberTests: XCTestCase {
    private var temporaryRoot: URL!
    private var transcriber: WhisperKitTranscriber!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let availability = ModelAvailabilityService(modelsRoot: temporaryRoot)
        transcriber = WhisperKitTranscriber(modelAvailability: availability)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        transcriber = nil
    }

    func testTranscribeFailsWhenModelNotDownloaded() async {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-model-test.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let job = TranscriptionJob(
            audioFileURL: audioURL,
            sourceFileName: audioURL.lastPathComponent,
            modelID: "base",
            whisperKitModelName: "base",
            modelDisplayName: "Base",
            languageID: "auto"
        )

        do {
            _ = try await transcriber.transcribe(job)
            XCTFail("Expected modelNotDownloaded error")
        } catch let error as AppError {
            XCTAssertEqual(error, .modelNotDownloaded("Base"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Word confidence

    func testMapWordsTrimsTextAndRoundsProbability() throws {
        let words = [
            WordTiming(word: " Hello", tokens: [1], start: 0.0, end: 0.4, probability: 0.97),
            WordTiming(word: " Hollis", tokens: [2], start: 0.4, end: 0.9, probability: 0.4237)
        ]

        let mapped = try XCTUnwrap(WhisperKitTranscriber.mapWords(words))

        XCTAssertEqual(mapped.map(\.text), ["Hello", "Hollis"])
        XCTAssertEqual(mapped[1].startTime, 0.4, accuracy: 0.0001)
        XCTAssertEqual(mapped[1].endTime, 0.9, accuracy: 0.0001)
        XCTAssertEqual(mapped[1].probability, 0.424)
    }

    func testMapWordsDropsWhitespaceOnlyWords() {
        XCTAssertNil(WhisperKitTranscriber.mapWords(nil))
        XCTAssertNil(WhisperKitTranscriber.mapWords([]))
        XCTAssertNil(WhisperKitTranscriber.mapWords([
            WordTiming(word: " ", tokens: [1], start: 0, end: 0.1, probability: 0.9)
        ]))
    }

    func testOffsetSegmentsMovesSegmentAndWordTimesOntoSourceTimeline() {
        let segment = TranscriptionSegment(
            start: 1.0,
            end: 2.5,
            text: " Second chunk",
            words: [WordTiming(word: " Second", tokens: [1], start: 1.0, end: 1.6, probability: 0.9)]
        )

        let shifted = WhisperKitTranscriber.offsetSegments([segment], by: 600)

        XCTAssertEqual(shifted[0].start, 601.0, accuracy: 0.001)
        XCTAssertEqual(shifted[0].end, 602.5, accuracy: 0.001)
        XCTAssertEqual(shifted[0].words?[0].start ?? 0, 601.0, accuracy: 0.001)
        XCTAssertEqual(shifted[0].words?[0].end ?? 0, 601.6, accuracy: 0.001)
    }

    func testOffsetSegmentsLeavesFirstChunkUnchanged() {
        let segment = TranscriptionSegment(start: 1.0, end: 2.5, text: " First chunk")

        let shifted = WhisperKitTranscriber.offsetSegments([segment], by: 0)

        XCTAssertEqual(shifted[0].start, 1.0)
        XCTAssertEqual(shifted[0].end, 2.5)
    }
}
