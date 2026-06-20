import AppKit
import Foundation

@MainActor
final class SelectionMonitor: ObservableObject {
    var onCorrectionStarted: (() -> Void)?
    var onCorrectionFinished: (() -> Void)?
    var onCorrectionResult: ((CorrectionResult) -> Void)?
    var onCorrectionError: ((String) -> Void)?
    var onSelectionCleared: (() -> Void)?

    private let settings: AppSettings
    private let accessibilityManager: AccessibilityManager
    private let embeddedEngine: CorrectionEngine
    private let fallbackSpellCheckerEngine: CorrectionEngine
    private let gectorEngineFactory: (AppSettings) throws -> CorrectionEngine
    private let geminiEngineFactory: (AppSettings) throws -> CorrectionEngine
    private var currentTask: Task<Void, Never>?
    private var lastSelectionSignature: SelectionProcessingSignature?
    private var lastSelectionProcessedAt: Date?

    init(
        settings: AppSettings = .shared,
        accessibilityManager: AccessibilityManager = .shared,
        embeddedEngine: CorrectionEngine = LanguageToolCorrectionEngine(),
        fallbackSpellCheckerEngine: CorrectionEngine = MacOSSpellCheckerEngine(),
        gectorEngineFactory: @escaping (AppSettings) throws -> CorrectionEngine = {
            try LanguageToolGECToRCorrectionEngine(
                languageToolEngine: LanguageToolCorrectionEngine(),
                gectorHelper: GECToRHTTPClient(
                    endpoint: $0.gectorHelperEndpoint,
                    timeout: $0.gectorRequestTimeout
                )
            )
        },
        geminiEngineFactory: @escaping (AppSettings) throws -> CorrectionEngine = {
            try GeminiCorrectionEngine(
                apiKey: $0.geminiAPIKey,
                model: $0.geminiModel
            )
        }
    ) {
        self.settings = settings
        self.accessibilityManager = accessibilityManager
        self.embeddedEngine = embeddedEngine
        self.fallbackSpellCheckerEngine = fallbackSpellCheckerEngine
        self.gectorEngineFactory = gectorEngineFactory
        self.geminiEngineFactory = geminiEngineFactory
    }

    func start() {
        // The app checks text only when the user invokes the configured shortcut or menu item.
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    func checkCurrentSelectionNow() async {
        guard settings.isEnabled, accessibilityManager.isTrusted else { return }

        let selectedText: String?
        if let accessibilitySelectedText = accessibilityManager.selectedText() {
            selectedText = accessibilitySelectedText
        } else {
            selectedText = await accessibilityManager.selectedTextFromClipboardFallback()
        }

        guard let selectedText else {
            onCorrectionError?("No selected text was found.")
            return
        }

        process(selectedText: selectedText)
    }

    func process(selectedText: String) {
        let normalizedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelectedText.isEmpty else { return }
        guard normalizedSelectedText.count <= settings.maxSelectedTextLength else { return }
        guard shouldShowPopup(for: normalizedSelectedText) else { return }
        guard shouldProcessSelection(normalizedSelectedText, with: selectionSignature(for: normalizedSelectedText)) else { return }

        currentTask?.cancel()
        onCorrectionStarted?()
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.onCorrectionFinished?()
                }
            }

            do {
                let result = try await self.activeEngine().correct(text: normalizedSelectedText)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.onCorrectionResult?(result)
                }
            } catch {
                await self.fallbackAfterEngineError(text: normalizedSelectedText, error: error)
            }
        }
    }

    private func shouldShowPopup(for text: String) -> Bool {
        let wordCount = text.split { !$0.isLetter }.count
        if wordCount <= 1 {
            return settings.showPopupForSingleWords
        }
        return settings.showPopupForSentences
    }

    private func activeEngine() throws -> CorrectionEngine {
        switch settings.correctionMode {
        case .embeddedLanguageTool:
            return embeddedEngine
        case .languageToolGECToR:
            return try gectorEngineFactory(settings)
        case .gemini:
            return try geminiEngineFactory(settings)
        }
    }

    private func shouldProcessSelection(_ text: String, with signature: SelectionProcessingSignature) -> Bool {
        let now = Date()

        if
            let lastSelectionProcessedAt,
            lastSelectionSignature?.textHash == signature.textHash,
            lastSelectionSignature?.correctionMode == signature.correctionMode,
            now.timeIntervalSince(lastSelectionProcessedAt) < 0.5
        {
            return false
        }

        lastSelectionSignature = signature
        lastSelectionProcessedAt = now
        return true
    }

    private func selectionSignature(for text: String) -> SelectionProcessingSignature {
        SelectionProcessingSignature(
            textHash: text.hashValue,
            correctionMode: settings.correctionMode,
            gectorHelperEndpoint: settings.gectorHelperEndpoint,
            gectorRequestTimeout: settings.gectorRequestTimeout,
            geminiModel: settings.geminiModel
        )
    }

    private func fallbackAfterEngineError(text: String, error: Error) async {
        Logger.correction.error("Correction engine failed: \(error.localizedDescription, privacy: .public)")
        onCorrectionError?(error.localizedDescription)
        do {
            let result = try await fallbackSpellCheckerEngine.correct(text: text)
            guard !Task.isCancelled else { return }
            onCorrectionResult?(result)
        } catch {
            onCorrectionError?(error.localizedDescription)
        }
    }
}

private struct SelectionProcessingSignature: Equatable {
    let textHash: Int
    let correctionMode: CorrectionMode
    let gectorHelperEndpoint: String
    let gectorRequestTimeout: Double
    let geminiModel: String
}
