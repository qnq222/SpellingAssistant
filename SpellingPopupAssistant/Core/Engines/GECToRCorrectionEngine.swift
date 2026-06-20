import Foundation

struct GECToRHelperResult: Equatable {
    let originalText: String
    let correctedText: String
    let issues: [GECToRHelperIssue]
}

struct GECToRHelperIssue: Equatable, Codable {
    let original: String
    let replacement: String?
    let message: String
}

protocol GECToRHelping {
    func improve(text: String) async throws -> GECToRHelperResult
}

enum GECToRCorrectionError: LocalizedError {
    case invalidEndpoint
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The GECToR helper endpoint could not be created."
        case .invalidResponse:
            return "The GECToR helper returned a response that could not be parsed."
        }
    }
}

final class GECToRHTTPClient: GECToRHelping {
    private struct CorrectionRequest: Encodable {
        let text: String
    }

    private struct CorrectionResponse: Decodable {
        let originalText: String?
        let correctedText: String
        let issues: [GECToRHelperIssue]?
    }

    private let endpoint: URL
    private let timeout: TimeInterval
    private let session: URLSession

    init(endpoint: URL, timeout: TimeInterval, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.session = session
    }

    convenience init(endpoint: String, timeout: TimeInterval, session: URLSession = .shared) throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GECToRCorrectionError.invalidEndpoint
        }

        self.init(endpoint: url, timeout: timeout, session: session)
    }

    func improve(text: String) async throws -> GECToRHelperResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CorrectionRequest(text: text))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw GECToRCorrectionError.invalidResponse
        }

        let helperResponse = try JSONDecoder().decode(CorrectionResponse.self, from: data)
        return GECToRHelperResult(
            originalText: helperResponse.originalText ?? text,
            correctedText: helperResponse.correctedText,
            issues: helperResponse.issues ?? []
        )
    }
}

final class LanguageToolGECToRCorrectionEngine: CorrectionEngine {
    private let languageToolEngine: CorrectionEngine
    private let spellingFallbackEngine: CorrectionEngine
    private let gectorHelper: GECToRHelping

    init(
        languageToolEngine: CorrectionEngine,
        spellingFallbackEngine: CorrectionEngine = MacOSSpellCheckerEngine(),
        gectorHelper: GECToRHelping
    ) {
        self.languageToolEngine = languageToolEngine
        self.spellingFallbackEngine = spellingFallbackEngine
        self.gectorHelper = gectorHelper
    }

    func correct(text: String) async throws -> CorrectionResult {
        let baseResult: CorrectionResult
        do {
            baseResult = try await languageToolEngine.correct(text: text)
        } catch {
            Logger.correction.error("LanguageTool failed before GECToR pass: \(error.localizedDescription, privacy: .public)")
            baseResult = CorrectionResult(
                originalText: text,
                correctedText: text,
                spellingIssueCount: 0,
                grammarIssueCount: 0,
                misspelledWordCount: 0,
                corrections: [],
                issues: []
            )
        }

        let spellingResult = await supplementWithFallbackSpelling(originalText: text, baseResult: baseResult)
        let localGrammarResult = supplementWithHighConfidenceGrammar(originalText: text, baseResult: spellingResult)

        guard shouldAskGECToR(toImprove: localGrammarResult.correctedText) else {
            return localGrammarResult
        }

        do {
            let helperResult = try await gectorHelper.improve(text: localGrammarResult.correctedText)
            return mergedResult(originalText: text, languageToolResult: localGrammarResult, helperResult: helperResult)
        } catch {
            Logger.correction.error("GECToR helper failed: \(error.localizedDescription, privacy: .public)")
            return localGrammarResult
        }
    }

    private func shouldAskGECToR(toImprove text: String) -> Bool {
        text.split { !$0.isLetter }.count > 1
    }

    private func mergedResult(
        originalText: String,
        languageToolResult: CorrectionResult,
        helperResult: GECToRHelperResult
    ) -> CorrectionResult {
        let improvedText = helperResult.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !improvedText.isEmpty, improvedText != languageToolResult.correctedText else {
            return languageToolResult
        }
        guard preservesNegationMeaning(from: languageToolResult.correctedText, to: improvedText) else {
            Logger.correction.error("Rejected GECToR correction because it removed negation meaning.")
            return languageToolResult
        }

        let gectorIssues = issues(from: helperResult, fallbackOriginal: languageToolResult.correctedText, fallbackReplacement: improvedText)
        let gectorCorrections = gectorIssues.compactMap { issue -> WordCorrection? in
            guard let replacement = issue.replacement else { return nil }
            return WordCorrection(original: issue.original, corrected: replacement)
        }

        return CorrectionResult(
            originalText: originalText,
            correctedText: improvedText,
            spellingIssueCount: languageToolResult.spellingIssueCount,
            grammarIssueCount: languageToolResult.grammarIssueCount + max(gectorIssues.count, 1),
            misspelledWordCount: languageToolResult.misspelledWordCount,
            corrections: languageToolResult.corrections + gectorCorrections,
            issues: languageToolResult.issues + gectorIssues
        )
    }

    private func issues(
        from helperResult: GECToRHelperResult,
        fallbackOriginal: String,
        fallbackReplacement: String
    ) -> [CorrectionIssue] {
        let issues = helperResult.issues.map {
            CorrectionIssue(
                kind: .grammar,
                original: $0.original,
                replacement: $0.replacement,
                message: $0.message
            )
        }

        if !issues.isEmpty {
            return issues
        }

        return [
            CorrectionIssue(
                kind: .grammar,
                original: fallbackOriginal,
                replacement: fallbackReplacement,
                message: "GECToR grammar improvement"
            )
        ]
    }

    private func supplementWithFallbackSpelling(originalText: String, baseResult: CorrectionResult) async -> CorrectionResult {
        do {
            let spellingResult = try await spellingFallbackEngine.correct(text: baseResult.correctedText)
            guard spellingResult.correctedText != baseResult.correctedText || !spellingResult.corrections.isEmpty else {
                return baseResult
            }

            let spellingIssues = spellingResult.corrections.map {
                CorrectionIssue(
                    kind: .spelling,
                    original: $0.original,
                    replacement: $0.corrected,
                    message: "Spelling"
                )
            }

            return CorrectionResult(
                originalText: originalText,
                correctedText: spellingResult.correctedText,
                spellingIssueCount: baseResult.spellingIssueCount + max(spellingResult.spellingIssueCount, spellingResult.corrections.count),
                grammarIssueCount: baseResult.grammarIssueCount,
                misspelledWordCount: baseResult.misspelledWordCount + spellingResult.misspelledWordCount,
                corrections: baseResult.corrections + spellingResult.corrections,
                issues: baseResult.issues + spellingIssues
            )
        } catch {
            Logger.correction.error("Fallback spelling pass failed before GECToR pass: \(error.localizedDescription, privacy: .public)")
            return baseResult
        }
    }

    private struct LocalGrammarRule {
        let pattern: String
        let template: String
        let message: String
    }

    private func supplementWithHighConfidenceGrammar(originalText: String, baseResult: CorrectionResult) -> CorrectionResult {
        let rules = [
            LocalGrammarRule(
                pattern: "\\b(users|customers|members|clients|people|they|we|you)\\s+has\\b",
                template: "$1 have",
                message: "Subject-verb agreement"
            ),
            LocalGrammarRule(
                pattern: "\\bhave\\s+receive\\b",
                template: "have received",
                message: "Verb form"
            ),
            LocalGrammarRule(
                pattern: "\\bhas\\s+receive\\b",
                template: "has received",
                message: "Verb form"
            ),
            LocalGrammarRule(
                pattern: "\\b(they|we|you|users|customers|members|clients|people)\\s+wasn't\\b",
                template: "$1 weren't",
                message: "Subject-verb agreement"
            ),
            LocalGrammarRule(
                pattern: "\\bto\\s+login\\b",
                template: "to log in",
                message: "Use the verb phrase here"
            ),
            LocalGrammarRule(
                pattern: "\\b(notification|message|email|update)\\s+but\\s+(they|he|she|we|I)\\b",
                template: "$1, but $2",
                message: "Add punctuation before contrast"
            )
        ]

        var correctedText = baseResult.correctedText
        var grammarIssues: [CorrectionIssue] = []
        var grammarCorrections: [WordCorrection] = []

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsText = correctedText as NSString
            let matches = regex.matches(in: correctedText, range: NSRange(location: 0, length: nsText.length))
            guard !matches.isEmpty else { continue }

            for match in matches.reversed() {
                let original = nsText.substring(with: match.range)
                let replacement = regex.replacementString(
                    for: match,
                    in: correctedText,
                    offset: 0,
                    template: rule.template
                )

                guard replacement != original else { continue }
                correctedText = (correctedText as NSString).replacingCharacters(in: match.range, with: replacement)
                grammarCorrections.append(WordCorrection(original: original, corrected: replacement))
                grammarIssues.append(CorrectionIssue(kind: .grammar, original: original, replacement: replacement, message: rule.message))
            }
        }

        guard !grammarIssues.isEmpty else {
            return baseResult
        }

        return CorrectionResult(
            originalText: originalText,
            correctedText: correctedText,
            spellingIssueCount: baseResult.spellingIssueCount,
            grammarIssueCount: baseResult.grammarIssueCount + grammarIssues.count,
            misspelledWordCount: baseResult.misspelledWordCount,
            corrections: baseResult.corrections + grammarCorrections.reversed(),
            issues: baseResult.issues + grammarIssues.reversed()
        )
    }

    private func preservesNegationMeaning(from original: String, to candidate: String) -> Bool {
        negationMarkerCount(in: candidate) >= negationMarkerCount(in: original)
    }

    private func negationMarkerCount(in text: String) -> Int {
        tokens(in: text).filter { token in
            token == "not"
                || token == "no"
                || token == "never"
                || token == "cannot"
                || token == "can't"
                || token == "won't"
                || token.hasSuffix("n't")
                || token == "unable"
        }.count
    }

    private func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.letters.contains(scalar) || scalar == "'" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
