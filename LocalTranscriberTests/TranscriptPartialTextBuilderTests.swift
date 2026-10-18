import XCTest
@testable import LocalTranscriber

final class TranscriptPartialTextBuilderTests: XCTestCase {
    func testJoinedPresentableTextRemovesSpecialTokens() {
        let text = TranscriptPartialTextBuilder.joinedPresentableText(from: [
            "<|startoftranscript|><|ja|><|transcribe|><|0.00|>こんにちは<|2.00|>",
            "<|startoftranscript|><|nocaptions|><|endoftext|>",
        ])

        XCTAssertEqual(text, "こんにちは")
    }

    func testAppendPresentableWindowTextAccumulatesAcrossCalls() {
        var accumulated = ""

        let first = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["こんにちは"],
            to: &accumulated
        )
        let second = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["世界"],
            to: &accumulated
        )

        XCTAssertEqual(first, "こんにちは")
        XCTAssertEqual(second, "こんにちは 世界")
        XCTAssertEqual(accumulated, "こんにちは 世界")
    }

    func testAppendPresentableWindowTextIgnoresTagOnlySegments() {
        var accumulated = ""

        let result = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["<|startoftranscript|><|nocaptions|><|endoftext|>"],
            to: &accumulated
        )

        XCTAssertNil(result)
        XCTAssertTrue(accumulated.isEmpty)
    }

    // MARK: - Differential tests (legacy [String] impl vs new String impl)

    /// Inline reconstruction of the old implementation. Used to verify behavioral equivalence with the new one.
    private func legacyAppend(from segmentTexts: [String], to accumulated: inout [String]) -> String? {
        let windowText = TranscriptPartialTextBuilder.joinedPresentableText(from: segmentTexts)
        guard !windowText.isEmpty else { return nil }
        accumulated.append(windowText)
        let partialText = accumulated.joined(separator: " ")
        return TranscriptTextSanitizer.presentableText(from: partialText)
    }

    func testDifferential_SingleSegment() {
        let inputs = [
            "こんにちは",
            "<|startoftranscript|><|ja|>こんにちは",
            "",
            "  spaces   here  ",
            "<|startoftranscript|><|nocaptions|>",
        ]
        for input in inputs {
            var oldAcc: [String] = []
            var newAcc = ""
            let oldResult = legacyAppend(from: [input], to: &oldAcc)
            let newResult = TranscriptPartialTextBuilder.appendPresentableWindowText(from: [input], to: &newAcc)
            XCTAssertEqual(oldResult, newResult, "Mismatch at input: \(input)")
        }
    }

    func testDifferential_MultiSegment_Window() {
        // Case with multiple segments in one window
        let windowInputs: [[String]] = [
            ["第一段", "第二段"],
            ["<|startoftranscript|><|ja|>第三段", "第四段"],
        ]
        var oldAcc: [String] = []
        var newAcc = ""
        for window in windowInputs {
            let oldResult = legacyAppend(from: window, to: &oldAcc)
            let newResult = TranscriptPartialTextBuilder.appendPresentableWindowText(from: window, to: &newAcc)
            XCTAssertEqual(oldResult, newResult, "Mismatch at window: \(window)")
        }
    }

    func testDifferential_MultiWindow_MixedTokens() {
        let windowTexts: [[String]] = [
            ["<|startoftranscript|><|ja|>第一段"],
            ["<|startoftranscript|><|nocaptions|>第二段"],
            ["第三段"],
            ["<|startoftranscript|><|en|>fourth"],
            ["  spaces   here  "],
        ]
        var oldAcc: [String] = []
        var newAcc = ""
        for window in windowTexts {
            let oldResult = legacyAppend(from: window, to: &oldAcc)
            let newResult = TranscriptPartialTextBuilder.appendPresentableWindowText(from: window, to: &newAcc)
            XCTAssertEqual(oldResult, newResult, "Mismatch at window: \(window)")
        }
    }

    func testDifferential_AllTagOnlyWindows() {
        let windowTexts: [[String]] = [
            ["<|startoftranscript|><|nocaptions|>"],
            ["<|startoftranscript|>"],
            ["<|endoftranscript|>"],
        ]
        var oldAcc: [String] = []
        var newAcc = ""
        for window in windowTexts {
            let oldResult = legacyAppend(from: window, to: &oldAcc)
            let newResult = TranscriptPartialTextBuilder.appendPresentableWindowText(from: window, to: &newAcc)
            XCTAssertEqual(oldResult, newResult, "Mismatch at window: \(window)")
            XCTAssertNil(newResult)
        }
    }

    func testDifferential_100Windows() {
        var oldAcc: [String] = []
        var newAcc = ""
        for i in 0..<100 {
            let input = "<|startoftranscript|><|ja|><|\(Double(i) * 0.5).00|>セグ\(i)"
            let oldResult = legacyAppend(from: [input], to: &oldAcc)
            let newResult = TranscriptPartialTextBuilder.appendPresentableWindowText(from: [input], to: &newAcc)
            XCTAssertEqual(oldResult, newResult, "Mismatch at index: \(i)")
        }
    }
}
