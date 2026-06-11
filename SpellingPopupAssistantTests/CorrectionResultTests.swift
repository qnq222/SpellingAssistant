import XCTest
@testable import SpellingPopupAssistant

final class CorrectionResultTests: XCTestCase {
    func testHasCorrectionsRequiresChangedTextAndCount() {
        let corrected = CorrectionResult(
            originalText: "recieved",
            correctedText: "received",
            misspelledWordCount: 1,
            corrections: [WordCorrection(original: "recieved", corrected: "received")]
        )
        let unchanged = CorrectionResult(
            originalText: "received",
            correctedText: "received",
            misspelledWordCount: 0,
            corrections: []
        )

        XCTAssertTrue(corrected.hasCorrections)
        XCTAssertFalse(unchanged.hasCorrections)
    }

    func testWordCorrectionEqualityIgnoresGeneratedID() {
        XCTAssertEqual(
            WordCorrection(original: "mesage", corrected: "message"),
            WordCorrection(original: "mesage", corrected: "message")
        )
    }
}
