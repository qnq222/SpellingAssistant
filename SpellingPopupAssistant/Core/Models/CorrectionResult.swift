import Foundation

struct CorrectionResult: Equatable {
    let originalText: String
    let correctedText: String
    let misspelledWordCount: Int
    let corrections: [WordCorrection]

    var hasCorrections: Bool {
        misspelledWordCount > 0 && originalText != correctedText
    }
}
