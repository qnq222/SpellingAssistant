import Foundation

protocol CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult
}
