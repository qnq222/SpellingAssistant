import XCTest
@testable import SpellingPopupAssistant

final class EngineManagerTests: XCTestCase {
    func testAnalyzeStartsLanguageToolLazily() async throws {
        let service = FakeLanguageToolService()
        let manager = EngineManager(service: service, inactivityTimeout: 60)

        let initiallyRunning = await manager.isRunning
        XCTAssertFalse(initiallyRunning)

        let result = try await manager.analyze(text: "I has a mesage.")

        XCTAssertEqual(service.startCallCount, 1)
        let runningAfterAnalyze = await manager.isRunning
        XCTAssertTrue(runningAfterAnalyze)
        XCTAssertEqual(result.grammarIssueCount, 1)
        XCTAssertEqual(result.spellingIssueCount, 1)
    }

    func testAnalyzeReusesRunningLanguageTool() async throws {
        let service = FakeLanguageToolService()
        let manager = EngineManager(service: service, inactivityTimeout: 60)

        _ = try await manager.analyze(text: "recieved")
        _ = try await manager.analyze(text: "mesage")

        XCTAssertEqual(service.startCallCount, 1)
        XCTAssertEqual(service.analyzeCallCount, 2)
    }

    func testInactivityTimeoutStopsLanguageTool() async throws {
        let service = FakeLanguageToolService()
        let manager = EngineManager(service: service, inactivityTimeout: 0.05)

        _ = try await manager.analyze(text: "recieved")
        try await Task.sleep(for: .milliseconds(120))

        let runningAfterTimeout = await manager.isRunning
        XCTAssertFalse(runningAfterTimeout)
        XCTAssertEqual(service.stopCallCount, 1)
    }
}

private final class FakeLanguageToolService: LanguageToolServing {
    private(set) var startCallCount = 0
    private(set) var analyzeCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isRunning = false
    var resourceUsage: EngineResourceUsage?

    func start() async throws {
        startCallCount += 1
        isRunning = true
    }

    func analyze(text: String) async throws -> CorrectionResult {
        analyzeCallCount += 1
        return CorrectionResult(
            originalText: text,
            correctedText: "I have a message.",
            spellingIssueCount: 1,
            grammarIssueCount: 1,
            misspelledWordCount: 1,
            corrections: [
                WordCorrection(original: "mesage", corrected: "message"),
                WordCorrection(original: "I has", corrected: "I have")
            ],
            issues: [
                CorrectionIssue(kind: .spelling, original: "mesage", replacement: "message", message: "Possible spelling mistake"),
                CorrectionIssue(kind: .grammar, original: "I has", replacement: "I have", message: "Subject-verb agreement")
            ]
        )
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }
}
