import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var isRecordingShortcut = false
    @State private var shortcutRecorderMonitor: Any?
    @State private var draftIsEnabled: Bool
    @State private var draftCorrectionMode: CorrectionMode
    @State private var draftMaxSelectedTextLength: Int
    @State private var draftShowPopupForSingleWords: Bool
    @State private var draftShowPopupForSentences: Bool
    @State private var draftAutoHideTimeout: Double
    @State private var draftGrammarCheckerEnabled: Bool
    @State private var draftOllamaEndpoint: String
    @State private var draftOllamaModel: String
    @State private var draftIsManualShortcutEnabled: Bool
    @State private var draftCheckSelectionShortcut: KeyboardShortcutSetting

    init(settings: AppSettings) {
        self.settings = settings
        _draftIsEnabled = State(initialValue: settings.isEnabled)
        _draftCorrectionMode = State(initialValue: settings.correctionMode)
        _draftMaxSelectedTextLength = State(initialValue: settings.maxSelectedTextLength)
        _draftShowPopupForSingleWords = State(initialValue: settings.showPopupForSingleWords)
        _draftShowPopupForSentences = State(initialValue: settings.showPopupForSentences)
        _draftAutoHideTimeout = State(initialValue: settings.autoHideTimeout)
        _draftGrammarCheckerEnabled = State(initialValue: settings.grammarCheckerEnabled)
        _draftOllamaEndpoint = State(initialValue: settings.ollamaEndpoint)
        _draftOllamaModel = State(initialValue: settings.ollamaModel)
        _draftIsManualShortcutEnabled = State(initialValue: settings.isManualShortcutEnabled)
        _draftCheckSelectionShortcut = State(initialValue: settings.checkSelectionShortcut)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable correction popup", isOn: $draftIsEnabled)

                Picker("Correction mode", selection: $draftCorrectionMode) {
                    ForEach(CorrectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Stepper("Maximum selected text length: \(draftMaxSelectedTextLength)", value: $draftMaxSelectedTextLength, in: 50...5000, step: 50)
                Toggle("Show popup for single words", isOn: $draftShowPopupForSingleWords)
                Toggle("Show popup for sentences", isOn: $draftShowPopupForSentences)
                Stepper("Auto-hide timeout: \(Int(draftAutoHideTimeout)) seconds", value: $draftAutoHideTimeout, in: 2...30, step: 1)

                Toggle("Enable manual shortcut fallback", isOn: $draftIsManualShortcutEnabled)

                LabeledContent("Manual check shortcut") {
                    HStack(spacing: 10) {
                        Text(isRecordingShortcut ? "Press any shortcut..." : draftCheckSelectionShortcut.title)
                            .foregroundStyle(draftIsManualShortcutEnabled ? (isRecordingShortcut ? .blue : .primary) : .secondary)
                            .frame(minWidth: 180, alignment: .leading)

                        Button(isRecordingShortcut ? "Cancel" : "Change") {
                            if isRecordingShortcut {
                                stopRecordingShortcut()
                            } else {
                                startRecordingShortcut()
                            }
                        }
                        .disabled(!draftIsManualShortcutEnabled)
                    }
                }
            }

            Section("Local AI with Ollama") {
                Toggle("Check grammar with local AI", isOn: $draftGrammarCheckerEnabled)
                TextField("Endpoint", text: $draftOllamaEndpoint)
                TextField("Model", text: $draftOllamaModel)
                Text("Grammar checking requires Ollama. When AI or grammar mode is enabled, selected text is sent only to the local Ollama server running on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Reset") {
                    loadDraftFromSettings()
                }
                Button("Save") {
                    saveDraftToSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540, height: 480)
        .onDisappear {
            stopRecordingShortcut()
        }
        .onChange(of: draftIsManualShortcutEnabled) { isEnabled in
            if !isEnabled {
                stopRecordingShortcut()
            }
        }
    }

    private func startRecordingShortcut() {
        stopRecordingShortcut()
        isRecordingShortcut = true

        shortcutRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecordingShortcut()
                return nil
            }

            if let shortcut = KeyboardShortcutSetting(event: event) {
                draftCheckSelectionShortcut = shortcut
                stopRecordingShortcut()
                return nil
            }

            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let shortcutRecorderMonitor {
            NSEvent.removeMonitor(shortcutRecorderMonitor)
            self.shortcutRecorderMonitor = nil
        }

        isRecordingShortcut = false
    }

    private func loadDraftFromSettings() {
        stopRecordingShortcut()
        draftIsEnabled = settings.isEnabled
        draftCorrectionMode = settings.correctionMode
        draftMaxSelectedTextLength = settings.maxSelectedTextLength
        draftShowPopupForSingleWords = settings.showPopupForSingleWords
        draftShowPopupForSentences = settings.showPopupForSentences
        draftAutoHideTimeout = settings.autoHideTimeout
        draftGrammarCheckerEnabled = settings.grammarCheckerEnabled
        draftOllamaEndpoint = settings.ollamaEndpoint
        draftOllamaModel = settings.ollamaModel
        draftIsManualShortcutEnabled = settings.isManualShortcutEnabled
        draftCheckSelectionShortcut = settings.checkSelectionShortcut
    }

    private func saveDraftToSettings() {
        stopRecordingShortcut()
        settings.isEnabled = draftIsEnabled
        settings.correctionMode = draftCorrectionMode
        settings.maxSelectedTextLength = draftMaxSelectedTextLength
        settings.showPopupForSingleWords = draftShowPopupForSingleWords
        settings.showPopupForSentences = draftShowPopupForSentences
        settings.autoHideTimeout = draftAutoHideTimeout
        settings.grammarCheckerEnabled = draftGrammarCheckerEnabled
        settings.ollamaEndpoint = draftOllamaEndpoint
        settings.ollamaModel = draftOllamaModel
        settings.isManualShortcutEnabled = draftIsManualShortcutEnabled
        settings.checkSelectionShortcut = draftCheckSelectionShortcut
    }
}
