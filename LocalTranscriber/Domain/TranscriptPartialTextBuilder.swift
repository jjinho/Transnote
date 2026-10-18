import Foundation

enum TranscriptPartialTextBuilder {
    static func joinedPresentableText(from segmentTexts: [String]) -> String {
        segmentTexts
            .compactMap(TranscriptTextSanitizer.presentableText(from:))
            .joined(separator: " ")
    }

    /// Incrementally joins a new window's text onto the accumulated text and returns it.
    ///
    /// `joinedPresentableText` selects only `presentableText` (sanitized, with no leftover special tokens)
    /// within each window, so each window can be treated as "clean text". Windows are always joined with a single
    /// space, which avoids the O(N^2 x regex) cost of re-sanitizing the entire accumulated text.
    /// Behavioral equivalence with the previous implementation is guaranteed by differential tests (TranscriptPartialTextBuilderTests).
    static func appendPresentableWindowText(
        from segmentTexts: [String],
        to accumulated: inout String
    ) -> String? {
        let windowText = joinedPresentableText(from: segmentTexts)
        guard !windowText.isEmpty else { return nil }

        accumulated = accumulated.isEmpty ? windowText : accumulated + " " + windowText
        return accumulated
    }
}
