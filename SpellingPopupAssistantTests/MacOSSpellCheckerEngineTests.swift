import XCTest
@testable import SpellingPopupAssistant

final class MacOSSpellCheckerEngineTests: XCTestCase {
    private var engine: MacOSSpellCheckerEngine!

    override func setUp() {
        super.setUp()
        engine = MacOSSpellCheckerEngine()
    }

    func testSingleMisspelledWordCorrection() async throws {
        let result = try await engine.correct(text: "recieved")

        XCTAssertEqual(result.correctedText.lowercased(), "received")
        XCTAssertEqual(result.misspelledWordCount, 1)
    }

    func testSentenceCorrection() async throws {
        let result = try await engine.correct(text: "I recieved the mesage.")

        XCTAssertEqual(result.correctedText, "I received the message.")
        XCTAssertEqual(result.misspelledWordCount, 2)
    }

    func testNoSpellingMistakes() async throws {
        let result = try await engine.correct(text: "I received the message.")

        XCTAssertEqual(result.correctedText, "I received the message.")
        XCTAssertEqual(result.misspelledWordCount, 0)
        XCTAssertTrue(result.corrections.isEmpty)
    }

    func testCapitalizationPreservation() async throws {
        let titleCase = try await engine.correct(text: "Recieved")
        let upperCase = try await engine.correct(text: "RECIEVED")

        XCTAssertEqual(titleCase.correctedText, "Received")
        XCTAssertEqual(upperCase.correctedText, "RECEIVED")
    }

    func testIgnoringURLs() async throws {
        let result = try await engine.correct(text: "Visit https://recieved.example.com now.")

        XCTAssertEqual(result.correctedText, "Visit https://recieved.example.com now.")
        XCTAssertEqual(result.misspelledWordCount, 0)
    }

    func testIgnoringEmails() async throws {
        let result = try await engine.correct(text: "Email recieved@example.com today.")

        XCTAssertEqual(result.correctedText, "Email recieved@example.com today.")
        XCTAssertEqual(result.misspelledWordCount, 0)
    }

    func testIgnoringNumbers() async throws {
        let result = try await engine.correct(text: "Build 12345 is ready.")

        XCTAssertEqual(result.correctedText, "Build 12345 is ready.")
        XCTAssertEqual(result.misspelledWordCount, 0)
    }

    func testCountingMisspelledWordsCorrectly() async throws {
        let result = try await engine.correct(text: "I recieved the mesage from the adminstrator.")

        XCTAssertEqual(result.correctedText, "I received the message from the administrator.")
        XCTAssertEqual(result.misspelledWordCount, 3)
        XCTAssertEqual(result.corrections.map(\.original), ["recieved", "mesage", "adminstrator"])
    }
}
