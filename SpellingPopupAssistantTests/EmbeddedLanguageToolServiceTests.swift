import XCTest
@testable import SpellingPopupAssistant

final class EmbeddedLanguageToolServiceTests: XCTestCase {
    func testMapsGrammarAndSpellingMatchesToCorrectedText() throws {
        let service = EmbeddedLanguageToolService(resourcesURL: URL(fileURLWithPath: "/tmp"))
        let json = """
        {
          "matches": [
            {
              "message": "Possible agreement error.",
              "shortMessage": "Agreement",
              "offset": 2,
              "length": 3,
              "replacements": [{ "value": "have" }],
              "rule": {
                "id": "HE_VERB_AGR",
                "issueType": "grammar",
                "category": { "id": "GRAMMAR", "name": "Grammar" }
              }
            },
            {
              "message": "Possible spelling mistake.",
              "shortMessage": "Spelling",
              "offset": 8,
              "length": 6,
              "replacements": [{ "value": "message" }],
              "rule": {
                "id": "MORFOLOGIK_RULE_EN_US",
                "issueType": "misspelling",
                "category": { "id": "TYPOS", "name": "Possible Typo" }
              }
            }
          ]
        }
        """

        let result = try service.correctionResult(
            fromLanguageToolResponse: XCTUnwrap(json.data(using: .utf8)),
            originalText: "I has a mesage."
        )

        XCTAssertEqual(result.correctedText, "I have a message.")
        XCTAssertEqual(result.grammarIssueCount, 1)
        XCTAssertEqual(result.spellingIssueCount, 1)
        XCTAssertEqual(result.totalIssueCount, 2)
    }

    func testSkipsOverlappingLowerPriorityMatches() throws {
        let service = EmbeddedLanguageToolService(resourcesURL: URL(fileURLWithPath: "/tmp"))
        let json = """
        {
          "matches": [
            {
              "message": "Replace whole phrase.",
              "shortMessage": "Grammar",
              "offset": 0,
              "length": 5,
              "replacements": [{ "value": "I have" }],
              "rule": {
                "id": "PHRASE_RULE",
                "issueType": "grammar",
                "category": { "id": "GRAMMAR", "name": "Grammar" }
              }
            },
            {
              "message": "Verb agreement.",
              "shortMessage": "Agreement",
              "offset": 2,
              "length": 3,
              "replacements": [{ "value": "have" }],
              "rule": {
                "id": "VERB_RULE",
                "issueType": "grammar",
                "category": { "id": "GRAMMAR", "name": "Grammar" }
              }
            }
          ]
        }
        """

        let result = try service.correctionResult(
            fromLanguageToolResponse: XCTUnwrap(json.data(using: .utf8)),
            originalText: "I has"
        )

        XCTAssertEqual(result.correctedText, "I have")
        XCTAssertEqual(result.grammarIssueCount, 1)
    }
}
