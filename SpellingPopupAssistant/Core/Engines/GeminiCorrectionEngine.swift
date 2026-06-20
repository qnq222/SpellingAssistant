import Foundation

enum GeminiCorrectionError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is missing."
        case .invalidEndpoint:
            return "The Gemini endpoint could not be created."
        case .invalidResponse:
            return "Gemini returned a response that could not be parsed."
        }
    }
}

final class GeminiCorrectionEngine: CorrectionEngine {
    private struct GenerateContentRequest: Encodable {
        let systemInstruction: GeminiContent
        let contents: [GeminiContent]
        let generationConfig: GenerationConfig

        enum CodingKeys: String, CodingKey {
            case systemInstruction = "system_instruction"
            case contents
            case generationConfig
        }
    }

    private struct GenerationConfig: Encodable {
        let temperature: Double
        let maxOutputTokens: Int
        let responseMimeType: String

        enum CodingKeys: String, CodingKey {
            case temperature
            case maxOutputTokens = "maxOutputTokens"
            case responseMimeType = "responseMimeType"
        }
    }

    private struct GeminiContent: Codable {
        let parts: [GeminiPart]
    }

    private struct GeminiPart: Codable {
        let text: String
    }

    private struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]
    }

    private struct Candidate: Decodable {
        let content: GeminiContent
    }

    private struct AIResult: Decodable {
        let correctedText: String
        let misspelledWordCount: Int
        let corrections: [AICorrection]
    }

    private struct AICorrection: Decodable {
        let original: String
        let corrected: String
    }

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw GeminiCorrectionError.missingAPIKey
        }

        self.apiKey = trimmedAPIKey
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func correct(text: String) async throws -> CorrectionResult {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiCorrectionError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: systemPrompt)]),
            contents: [GeminiContent(parts: [GeminiPart(text: userPrompt(for: text))])],
            generationConfig: GenerationConfig(
                temperature: 0,
                maxOutputTokens: 300,
                responseMimeType: "application/json"
            )
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw GeminiCorrectionError.invalidResponse
        }

        let generateResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        guard let content = generateResponse.candidates.first?.content.parts.first?.text else {
            throw GeminiCorrectionError.invalidResponse
        }

        guard let resultData = extractJSON(from: content).data(using: .utf8) else {
            throw GeminiCorrectionError.invalidResponse
        }

        let aiResult = try JSONDecoder().decode(AIResult.self, from: resultData)
        let corrections = aiResult.corrections.map { WordCorrection(original: $0.original, corrected: $0.corrected) }
        let issues = corrections.map {
            CorrectionIssue(
                kind: .grammar,
                original: $0.original,
                replacement: $0.corrected,
                message: "Grammar/Style"
            )
        }

        return CorrectionResult(
            originalText: text,
            correctedText: aiResult.correctedText,
            spellingIssueCount: 0,
            grammarIssueCount: aiResult.misspelledWordCount,
            misspelledWordCount: aiResult.misspelledWordCount,
            corrections: corrections,
            issues: issues
        )
    }

    private var systemPrompt: String {
        """
        You are a fast proofreading engine.
        Fix spelling, grammar, tense, agreement, article, punctuation, word-form, and clarity issues.
        Preserve meaning. Do not add ideas.
        Return JSON only:
        {
          "correctedText": "string",
          "misspelledWordCount": number,
          "corrections": [
            {
              "original": "string",
              "corrected": "string"
            }
          ]
        }

        Count all spelling, grammar, and clarity fixes in misspelledWordCount.
        """
    }

    private func userPrompt(for text: String) -> String {
        """
        Text:
        \"\"\"
        \(text)
        \"\"\"
        """
    }

    private func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }

        return String(text[start...end])
    }
}
