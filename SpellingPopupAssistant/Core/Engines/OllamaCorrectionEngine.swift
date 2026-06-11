import Foundation

enum OllamaCorrectionError: LocalizedError {
    case invalidEndpoint
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The configured Ollama endpoint is invalid."
        case .invalidResponse:
            return "Ollama returned a response that could not be parsed."
        }
    }
}

final class OllamaCorrectionEngine: CorrectionEngine {
    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
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

    private let endpoint: URL
    private let model: String
    private let includesGrammarCorrection: Bool
    private let session: URLSession

    init(endpoint: String, model: String, includesGrammarCorrection: Bool = false, session: URLSession = .shared) throws {
        guard let baseURL = URL(string: endpoint) else {
            throw OllamaCorrectionError.invalidEndpoint
        }

        self.endpoint = baseURL.appendingPathComponent("api/generate")
        self.model = model
        self.includesGrammarCorrection = includesGrammarCorrection
        self.session = session
    }

    func correct(text: String) async throws -> CorrectionResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(GenerateRequest(model: model, prompt: prompt(for: text, includesGrammarCorrection: includesGrammarCorrection), stream: false))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw OllamaCorrectionError.invalidResponse
        }

        let generateResponse = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let jsonPayload = extractJSON(from: generateResponse.response)
        guard let resultData = jsonPayload.data(using: .utf8) else {
            throw OllamaCorrectionError.invalidResponse
        }

        let aiResult = try JSONDecoder().decode(AIResult.self, from: resultData)
        return CorrectionResult(
            originalText: text,
            correctedText: aiResult.correctedText,
            misspelledWordCount: aiResult.misspelledWordCount,
            corrections: aiResult.corrections.map { WordCorrection(original: $0.original, corrected: $0.corrected) }
        )
    }

    private func prompt(for text: String, includesGrammarCorrection: Bool) -> String {
        if includesGrammarCorrection {
            return """
            Correct spelling and grammar mistakes in the following text.
            Keep the original meaning.
            Do not rewrite style unless required to fix grammar.
            Do not add new ideas.
            Return valid JSON only with this schema:
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

            The misspelledWordCount field should count spelling and grammar issues found.

            Text:
            \"\"\"
            \(text)
            \"\"\"
            """
        }

        return """
        Correct only spelling mistakes in the following text.
        Do not rewrite style.
        Do not change meaning.
        Do not improve grammar unless required for spelling.
        Return valid JSON only with this schema:
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
