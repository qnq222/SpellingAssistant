import AppKit
import Foundation

@MainActor
final class SelectionMonitor: ObservableObject {
    var onCorrectionResult: ((CorrectionResult) -> Void)?
    var onCorrectionError: ((String) -> Void)?
    var onSelectionCleared: (() -> Void)?

    private let settings: AppSettings
    private let accessibilityManager: AccessibilityManager
    private let localEngine: CorrectionEngine
    private var timer: Timer?
    private var globalSelectionChangeMonitor: Any?
    private var localSelectionChangeMonitor: Any?
    private var lastSelectedText = ""
    private var currentTask: Task<Void, Never>?
    private var delayedPollTask: Task<Void, Never>?
    private var isPollingSelection = false

    init(
        settings: AppSettings = .shared,
        accessibilityManager: AccessibilityManager = .shared,
        localEngine: CorrectionEngine = MacOSSpellCheckerEngine()
    ) {
        self.settings = settings
        self.accessibilityManager = accessibilityManager
        self.localEngine = localEngine
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollSelection()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        Task { @MainActor [weak self] in
            await self?.pollSelection()
        }

        installSelectionChangeMonitors()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        delayedPollTask?.cancel()
        delayedPollTask = nil
        currentTask?.cancel()

        if let globalSelectionChangeMonitor {
            NSEvent.removeMonitor(globalSelectionChangeMonitor)
            self.globalSelectionChangeMonitor = nil
        }

        if let localSelectionChangeMonitor {
            NSEvent.removeMonitor(localSelectionChangeMonitor)
            self.localSelectionChangeMonitor = nil
        }
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

        process(selectedText: selectedText, allowRepeatedSelection: true)
    }

    private func pollSelection() async {
        guard settings.isEnabled, accessibilityManager.isTrusted else { return }
        guard !isPollingSelection else { return }
        isPollingSelection = true
        defer { isPollingSelection = false }

        guard let selectedText = accessibilityManager.selectedText() else {
            if accessibilityManager.canUseClipboardSelectionFallbackForFrontmostApp, !lastSelectedText.isEmpty {
                return
            }

            if !lastSelectedText.isEmpty {
                lastSelectedText = ""
                onSelectionCleared?()
            }
            return
        }

        process(selectedText: selectedText, allowRepeatedSelection: false)
    }

    private func installSelectionChangeMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .keyUp]

        globalSelectionChangeMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSelectionPoll()
            }
        }

        localSelectionChangeMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.scheduleSelectionPoll()
            }
            return event
        }
    }

    private func scheduleSelectionPoll() {
        delayedPollTask?.cancel()
        delayedPollTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.pollSelection()
        }
    }

    private func process(selectedText: String, allowRepeatedSelection: Bool) {
        let normalizedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelectedText.isEmpty else { return }
        guard allowRepeatedSelection || normalizedSelectedText != lastSelectedText else { return }
        guard normalizedSelectedText.count <= settings.maxSelectedTextLength else { return }
        guard shouldShowPopup(for: normalizedSelectedText) else { return }
        
        lastSelectedText = normalizedSelectedText
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.activeEngine().correct(text: normalizedSelectedText)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.onCorrectionResult?(result)
                }
            } catch {
                await MainActor.run {
                    self.fallbackAfterEngineError(text: normalizedSelectedText, error: error)
                }
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
        if settings.grammarCheckerEnabled {
            return try OllamaCorrectionEngine(
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel,
                includesGrammarCorrection: true
            )
        }

        switch settings.correctionMode {
        case .localSpellChecker:
            return localEngine
        case .ollama:
            return try OllamaCorrectionEngine(
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel
            )
        }
    }

    private func fallbackAfterEngineError(text: String, error: Error) {
        onCorrectionError?(error.localizedDescription)
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.localEngine.correct(text: text)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.onCorrectionResult?(result)
                }
            } catch {
                await MainActor.run {
                    self.onCorrectionError?(error.localizedDescription)
                }
            }
        }
    }
}
