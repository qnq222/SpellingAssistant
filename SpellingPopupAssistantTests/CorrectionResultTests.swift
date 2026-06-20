import Foundation
import XCTest
@testable import SpellingPopupAssistant

final class CorrectionResultTests: XCTestCase {
    func testHasCorrectionsUsesChangedTextOrReportedIssues() {
        let corrected = CorrectionResult(
            originalText: "recieved",
            correctedText: "received",
            misspelledWordCount: 1,
            corrections: [WordCorrection(original: "recieved", corrected: "received")]
        )
        let changedTextWithBadCount = CorrectionResult(
            originalText: "He go home.",
            correctedText: "He goes home.",
            misspelledWordCount: 0,
            corrections: []
        )
        let unchanged = CorrectionResult(
            originalText: "received",
            correctedText: "received",
            misspelledWordCount: 0,
            corrections: []
        )

        XCTAssertTrue(corrected.hasCorrections)
        XCTAssertTrue(changedTextWithBadCount.hasCorrections)
        XCTAssertFalse(unchanged.hasCorrections)
    }

    func testWordCorrectionEqualityIgnoresGeneratedID() {
        XCTAssertEqual(
            WordCorrection(original: "mesage", corrected: "message"),
            WordCorrection(original: "mesage", corrected: "message")
        )
    }
}

final class LanguageToolGECToRCorrectionEngineTests: XCTestCase {
    func testUsesGECToRToImproveLanguageToolSentenceResult() async throws {
        let languageToolEngine = CountingCorrectionEngine(
            correctedText: "He go to school yesterday.",
            spellingIssueCount: 1,
            grammarIssueCount: 0,
            misspelledWordCount: 1
        )
        let helper = StubGECToRHelper(result: GECToRHelperResult(
            originalText: "He go to school yesterday.",
            correctedText: "He went to school yesterday.",
            issues: [
                GECToRHelperIssue(
                    original: "go",
                    replacement: "went",
                    message: "Verb tense correction"
                )
            ]
        ))
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: languageToolEngine,
            spellingFallbackEngine: IdentityCorrectionEngine(),
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "He go to schol yesterday.")

        XCTAssertEqual(helper.receivedTexts, ["He go to school yesterday."])
        XCTAssertEqual(result.originalText, "He go to schol yesterday.")
        XCTAssertEqual(result.correctedText, "He went to school yesterday.")
        XCTAssertEqual(result.spellingIssueCount, 1)
        XCTAssertEqual(result.grammarIssueCount, 1)
        XCTAssertEqual(result.misspelledWordCount, 1)
        XCTAssertEqual(result.issues.last?.message, "Verb tense correction")
    }

    func testKeepsLanguageToolResultWhenGECToRFails() async throws {
        let languageToolEngine = CountingCorrectionEngine(correctedText: "He go to school yesterday.")
        let helper = StubGECToRHelper(error: GECToRCorrectionError.invalidResponse)
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: languageToolEngine,
            spellingFallbackEngine: IdentityCorrectionEngine(),
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "He go to schol yesterday.")

        XCTAssertEqual(result.correctedText, "He go to school yesterday.")
        XCTAssertEqual(helper.receivedTexts, ["He go to school yesterday."])
    }

    func testUsesGECToREvenWhenLanguageToolFails() async throws {
        let helper = StubGECToRHelper(result: GECToRHelperResult(
            originalText: "He go to school two yesterday",
            correctedText: "He went to school two yesterday",
            issues: [
                GECToRHelperIssue(
                    original: "go",
                    replacement: "went",
                    message: "GECToR grammar improvement"
                )
            ]
        ))
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: ThrowingCorrectionEngine(),
            spellingFallbackEngine: IdentityCorrectionEngine(),
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "He go to school two yesterday")

        XCTAssertEqual(helper.receivedTexts, ["He go to school two yesterday"])
        XCTAssertEqual(result.correctedText, "He went to school two yesterday")
        XCTAssertEqual(result.spellingIssueCount, 0)
        XCTAssertEqual(result.grammarIssueCount, 1)
    }

    func testUsesFallbackSpellingBeforeGECToRWhenLanguageToolFails() async throws {
        let spellingEngine = CountingCorrectionEngine(
            correctedText: "He go to school yesterday.",
            spellingIssueCount: 1,
            grammarIssueCount: 0,
            misspelledWordCount: 1
        )
        let helper = StubGECToRHelper(result: GECToRHelperResult(
            originalText: "He go to school yesterday.",
            correctedText: "He went to school yesterday.",
            issues: [
                GECToRHelperIssue(
                    original: "go",
                    replacement: "went",
                    message: "GECToR grammar improvement"
                )
            ]
        ))
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: ThrowingCorrectionEngine(),
            spellingFallbackEngine: spellingEngine,
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "He go to schol yesterday.")

        XCTAssertEqual(helper.receivedTexts, ["He go to school yesterday."])
        XCTAssertEqual(result.correctedText, "He went to school yesterday.")
        XCTAssertEqual(result.spellingIssueCount, 1)
        XCTAssertEqual(result.grammarIssueCount, 1)
        XCTAssertTrue(result.issues.contains {
            $0.kind == .spelling && $0.original == "He go to schol yesterday." && $0.replacement == "He go to school yesterday."
        })
        XCTAssertTrue(result.issues.contains {
            $0.kind == .grammar && $0.original == "go" && $0.replacement == "went"
        })
    }

    func testKeepsLocalGrammarResultWhenGECToRDropsNegation() async throws {
        let spellingEngine = CountingCorrectionEngine(
            correctedText: "The users has receive the notification but they wasn't able to login.",
            spellingIssueCount: 2,
            grammarIssueCount: 0,
            misspelledWordCount: 2
        )
        let helper = StubGECToRHelper(result: GECToRHelperResult(
            originalText: "The users have received the notification, but they weren't able to log in.",
            correctedText: "The users had received the notification but they were able to login.",
            issues: [
                GECToRHelperIssue(
                    original: "weren't",
                    replacement: "were",
                    message: "Unsafe grammar improvement"
                )
            ]
        ))
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: ThrowingCorrectionEngine(),
            spellingFallbackEngine: spellingEngine,
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "The users has recieve the notificaton but they wasn't able to login.")

        XCTAssertEqual(helper.receivedTexts, ["The users have received the notification, but they weren't able to log in."])
        XCTAssertEqual(result.correctedText, "The users have received the notification, but they weren't able to log in.")
        XCTAssertFalse(result.correctedText.contains("were able"))
        XCTAssertTrue(result.issues.contains {
            $0.kind == .grammar && $0.original == "users has" && $0.replacement == "users have"
        })
        XCTAssertTrue(result.issues.contains {
            $0.kind == .grammar && $0.original == "they wasn't" && $0.replacement == "they weren't"
        })
    }

    func testSkipsGECToRForSingleWords() async throws {
        let languageToolEngine = CountingCorrectionEngine(correctedText: "received")
        let helper = StubGECToRHelper(result: GECToRHelperResult(
            originalText: "received",
            correctedText: "receive",
            issues: []
        ))
        let engine = LanguageToolGECToRCorrectionEngine(
            languageToolEngine: languageToolEngine,
            spellingFallbackEngine: IdentityCorrectionEngine(),
            gectorHelper: helper
        )

        let result = try await engine.correct(text: "recieved")

        XCTAssertEqual(result.correctedText, "received")
        XCTAssertTrue(helper.receivedTexts.isEmpty)
    }
}

@MainActor
final class SelectionMonitorTests: XCTestCase {
    func testChangingCorrectionModeAllowsSameSelectionToBeProcessedAgain() async throws {
        let suiteName = "SelectionMonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.correctionMode = .embeddedLanguageTool

        let embeddedEngine = CountingCorrectionEngine(correctedText: "I have a message.")
        let gectorEngine = CountingCorrectionEngine(correctedText: "I have a better message.")
        let geminiEngine = CountingCorrectionEngine(correctedText: "I have a clearer message.")
        let monitor = SelectionMonitor(
            settings: settings,
            embeddedEngine: embeddedEngine,
            fallbackSpellCheckerEngine: CountingCorrectionEngine(correctedText: "fallback"),
            gectorEngineFactory: { _ in gectorEngine },
            geminiEngineFactory: { _ in geminiEngine }
        )

        var results: [CorrectionResult] = []
        let firstResult = expectation(description: "First correction result")
        monitor.onCorrectionResult = { result in
            results.append(result)
            firstResult.fulfill()
        }

        monitor.process(selectedText: "I has a mesage.")
        await fulfillment(of: [firstResult], timeout: 1)

        XCTAssertEqual(embeddedEngine.callCount, 1)
        XCTAssertEqual(results.last?.correctedText, "I have a message.")

        monitor.process(selectedText: "I has a mesage.")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(embeddedEngine.callCount, 1)

        let secondResult = expectation(description: "Second correction result")
        monitor.onCorrectionResult = { result in
            results.append(result)
            secondResult.fulfill()
        }

        settings.correctionMode = .languageToolGECToR
        monitor.process(selectedText: "I has a mesage.")
        await fulfillment(of: [secondResult], timeout: 1)

        XCTAssertEqual(gectorEngine.callCount, 1)
        XCTAssertEqual(results.last?.correctedText, "I have a better message.")
    }

    func testSameSelectionCanBeProcessedAgainAfterDebounceWindow() async throws {
        let suiteName = "SelectionMonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        let embeddedEngine = CountingCorrectionEngine(correctedText: "I have a message.")
        let monitor = SelectionMonitor(
            settings: settings,
            embeddedEngine: embeddedEngine,
            fallbackSpellCheckerEngine: CountingCorrectionEngine(correctedText: "fallback")
        )

        let firstResult = expectation(description: "First correction result")
        monitor.onCorrectionResult = { _ in
            firstResult.fulfill()
        }

        monitor.process(selectedText: "I has a mesage.")
        await fulfillment(of: [firstResult], timeout: 1)

        try await Task.sleep(nanoseconds: 600_000_000)

        let secondResult = expectation(description: "Second correction result")
        monitor.onCorrectionResult = { _ in
            secondResult.fulfill()
        }

        monitor.process(selectedText: "I has a mesage.")
        await fulfillment(of: [secondResult], timeout: 1)

        XCTAssertEqual(embeddedEngine.callCount, 2)
    }
}

private final class CountingCorrectionEngine: CorrectionEngine {
    private let correctedText: String
    private let spellingIssueCount: Int
    private let grammarIssueCount: Int
    private let misspelledWordCount: Int
    private(set) var callCount = 0

    init(
        correctedText: String,
        spellingIssueCount: Int? = nil,
        grammarIssueCount: Int = 0,
        misspelledWordCount: Int? = nil
    ) {
        self.correctedText = correctedText
        self.spellingIssueCount = spellingIssueCount ?? (correctedText.isEmpty ? 0 : 1)
        self.grammarIssueCount = grammarIssueCount
        self.misspelledWordCount = misspelledWordCount ?? (correctedText.isEmpty ? 0 : 1)
    }

    func correct(text: String) async throws -> CorrectionResult {
        callCount += 1
        return CorrectionResult(
            originalText: text,
            correctedText: correctedText,
            spellingIssueCount: text == correctedText ? 0 : spellingIssueCount,
            grammarIssueCount: text == correctedText ? 0 : grammarIssueCount,
            misspelledWordCount: text == correctedText ? 0 : misspelledWordCount,
            corrections: text == correctedText ? [] : [WordCorrection(original: text, corrected: correctedText)]
        )
    }
}

private struct ThrowingCorrectionEngine: CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult {
        throw GECToRCorrectionError.invalidResponse
    }
}

private struct IdentityCorrectionEngine: CorrectionEngine {
    func correct(text: String) async throws -> CorrectionResult {
        CorrectionResult(
            originalText: text,
            correctedText: text,
            misspelledWordCount: 0,
            corrections: []
        )
    }
}

private final class StubGECToRHelper: GECToRHelping {
    private let result: GECToRHelperResult?
    private let error: Error?
    private(set) var receivedTexts: [String] = []

    init(result: GECToRHelperResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func improve(text: String) async throws -> GECToRHelperResult {
        receivedTexts.append(text)
        if let error {
            throw error
        }

        return try XCTUnwrap(result)
    }
}
