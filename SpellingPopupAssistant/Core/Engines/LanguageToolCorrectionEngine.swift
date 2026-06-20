import Foundation

final class LanguageToolCorrectionEngine: CorrectionEngine {
    private let engineManager: EngineManager

    init(engineManager: EngineManager = .shared) {
        self.engineManager = engineManager
    }

    func correct(text: String) async throws -> CorrectionResult {
        try await engineManager.analyze(text: text)
    }
}
