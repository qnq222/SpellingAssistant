import AppKit
import Foundation

final class MacOSSpellCheckerEngine: CorrectionEngine {
    private let spellChecker: NSSpellChecker

    init(spellChecker: NSSpellChecker = .shared) {
        self.spellChecker = spellChecker
    }

    func correct(text: String) async throws -> CorrectionResult {
        let tokens = tokenize(text)
        var correctedText = ""
        var corrections: [WordCorrection] = []
        let language = spellChecker.language()
        let tag = NSSpellChecker.uniqueSpellDocumentTag()

        defer {
            spellChecker.closeSpellDocument(withTag: tag)
        }

        for token in tokens {
            guard token.isWord, shouldCheck(token.value, context: token.context) else {
                correctedText += token.value
                continue
            }

            let range = NSRange(location: 0, length: (token.value as NSString).length)
            let misspelledRange = spellChecker.checkSpelling(of: token.value, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)

            guard misspelledRange.location != NSNotFound, misspelledRange.location == 0, misspelledRange.length == range.length else {
                correctedText += token.value
                continue
            }

            let guesses = spellChecker.guesses(forWordRange: range, in: token.value, language: language, inSpellDocumentWithTag: tag)
            guard let firstGuess = guesses?.first, !firstGuess.isEmpty else {
                correctedText += token.value
                continue
            }

            let replacement = preserveCapitalization(from: token.value, applyingTo: firstGuess)
            correctedText += replacement
            corrections.append(WordCorrection(original: token.value, corrected: replacement))
        }

        return CorrectionResult(
            originalText: text,
            correctedText: correctedText,
            misspelledWordCount: corrections.count,
            corrections: corrections
        )
    }

    private struct Token {
        let value: String
        let isWord: Bool
        let context: String
    }

    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var segment = ""
        var segmentIsWhitespace: Bool?

        for scalar in text.unicodeScalars {
            let character = String(scalar)
            let isWhitespace = CharacterSet.whitespacesAndNewlines.contains(scalar)

            if segmentIsWhitespace == nil {
                segmentIsWhitespace = isWhitespace
                segment = character
            } else if segmentIsWhitespace == isWhitespace {
                segment += character
            } else {
                tokens.append(contentsOf: tokenizeSegment(segment, isWhitespace: segmentIsWhitespace ?? false))
                segment = character
                segmentIsWhitespace = isWhitespace
            }
        }

        if !segment.isEmpty {
            tokens.append(contentsOf: tokenizeSegment(segment, isWhitespace: segmentIsWhitespace ?? false))
        }

        return tokens
    }

    private func tokenizeSegment(_ segment: String, isWhitespace: Bool) -> [Token] {
        guard !isWhitespace else {
            return [Token(value: segment, isWord: false, context: segment)]
        }

        var tokens: [Token] = []
        var current = ""
        var currentIsWord: Bool?

        for scalar in segment.unicodeScalars {
            let character = String(scalar)
            let isWordCharacter = CharacterSet.letters.contains(scalar) || scalar == "'"

            if currentIsWord == nil {
                currentIsWord = isWordCharacter
                current = character
            } else if currentIsWord == isWordCharacter {
                current += character
            } else {
                tokens.append(Token(value: current, isWord: currentIsWord ?? false, context: segment))
                current = character
                currentIsWord = isWordCharacter
            }
        }

        if !current.isEmpty {
            tokens.append(Token(value: current, isWord: currentIsWord ?? false, context: segment))
        }

        return tokens
    }

    private func shouldCheck(_ word: String, context: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard trimmed.count >= 2 else { return false }
        guard !isProtectedContext(context) else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard !trimmed.contains("_") else { return false }
        guard !trimmed.contains("/") else { return false }
        guard !trimmed.contains("@") else { return false }
        guard !isAcronym(trimmed) else { return false }
        guard !isLikelyURL(trimmed) else { return false }
        guard !isLikelyEmail(trimmed) else { return false }
        guard !isLikelyCodeToken(trimmed) else { return false }
        return true
    }

    private func isProtectedContext(_ context: String) -> Bool {
        let lowercased = context.lowercased()
        return lowercased.contains("://")
            || lowercased.hasPrefix("www.")
            || lowercased.contains("@")
            || lowercased.contains("/")
            || lowercased.contains("\\")
            || lowercased.contains("_")
            || lowercased.contains("`")
    }

    private func isAcronym(_ word: String) -> Bool {
        word.count > 1 && word.count <= 5 && word == word.uppercased()
    }

    private func isLikelyURL(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        return lowercased.hasPrefix("http") || lowercased.hasPrefix("www.") || lowercased.contains(".com") || lowercased.contains(".org") || lowercased.contains(".net")
    }

    private func isLikelyEmail(_ word: String) -> Bool {
        word.contains("@") && word.contains(".")
    }

    private func isLikelyCodeToken(_ word: String) -> Bool {
        word.contains("{") || word.contains("}") || word.contains("(") || word.contains(")") || word.contains("=") || word.contains(";")
    }

    private func preserveCapitalization(from original: String, applyingTo suggestion: String) -> String {
        if original == original.uppercased() {
            return suggestion.uppercased()
        }

        guard let first = original.first, first.isUppercase else {
            return suggestion.lowercased()
        }

        return suggestion.prefix(1).uppercased() + suggestion.dropFirst().lowercased()
    }
}
