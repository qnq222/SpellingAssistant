import Foundation

struct CorrectionResult: Equatable {
    let originalText: String
    let correctedText: String
    let spellingIssueCount: Int
    let grammarIssueCount: Int
    let misspelledWordCount: Int
    let corrections: [WordCorrection]
    let issues: [CorrectionIssue]

    init(
        originalText: String,
        correctedText: String,
        spellingIssueCount: Int? = nil,
        grammarIssueCount: Int = 0,
        misspelledWordCount: Int,
        corrections: [WordCorrection],
        issues: [CorrectionIssue] = []
    ) {
        self.originalText = originalText
        self.correctedText = correctedText
        self.spellingIssueCount = spellingIssueCount ?? misspelledWordCount
        self.grammarIssueCount = grammarIssueCount
        self.misspelledWordCount = misspelledWordCount
        self.corrections = corrections
        self.issues = issues
    }

    var totalIssueCount: Int {
        spellingIssueCount + grammarIssueCount
    }

    var hasCorrections: Bool {
        originalText != correctedText || !corrections.isEmpty || !issues.isEmpty || totalIssueCount > 0
    }
}

struct CorrectionIssue: Equatable, Identifiable, Codable {
    enum IssueKind: String, Codable {
        case spelling
        case grammar
    }

    let id: UUID
    let kind: IssueKind
    let original: String
    let replacement: String?
    let message: String

    init(
        id: UUID = UUID(),
        kind: IssueKind,
        original: String,
        replacement: String?,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.original = original
        self.replacement = replacement
        self.message = message
    }

    static func == (lhs: CorrectionIssue, rhs: CorrectionIssue) -> Bool {
        lhs.kind == rhs.kind
            && lhs.original == rhs.original
            && lhs.replacement == rhs.replacement
            && lhs.message == rhs.message
    }
}
