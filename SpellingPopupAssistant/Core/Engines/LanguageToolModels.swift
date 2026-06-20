import Foundation

struct LanguageToolAnalysis: Equatable {
    let result: CorrectionResult
}

struct EngineResourceUsage: Equatable {
    let residentMemoryBytes: UInt64
    let sampledAt: Date
}

enum LanguageToolError: LocalizedError {
    case missingBundleResource(String)
    case processFailedToStart
    case serverUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingBundleResource(let path):
            return "Embedded LanguageTool resource is missing: \(path)"
        case .processFailedToStart:
            return "Embedded LanguageTool could not be started."
        case .serverUnavailable:
            return "Embedded LanguageTool did not become ready in time."
        case .invalidResponse:
            return "Embedded LanguageTool returned a response that could not be parsed."
        }
    }
}
