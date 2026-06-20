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
    @State private var draftIsAutoHideEnabled: Bool
    @State private var draftAutoHideTimeout: Double
    @State private var draftGECToRHelperEndpoint: String
    @State private var draftGECToRRequestTimeout: Double
    @State private var draftGeminiAPIKey: String
    @State private var draftGeminiModel: String
    @State private var draftIsManualShortcutEnabled: Bool
    @State private var draftCheckSelectionShortcut: KeyboardShortcutSetting

    init(settings: AppSettings) {
        self.settings = settings
        _draftIsEnabled = State(initialValue: settings.isEnabled)
        _draftCorrectionMode = State(initialValue: settings.correctionMode)
        _draftMaxSelectedTextLength = State(initialValue: settings.maxSelectedTextLength)
        _draftShowPopupForSingleWords = State(initialValue: settings.showPopupForSingleWords)
        _draftShowPopupForSentences = State(initialValue: settings.showPopupForSentences)
        _draftIsAutoHideEnabled = State(initialValue: settings.isAutoHideEnabled)
        _draftAutoHideTimeout = State(initialValue: settings.autoHideTimeout)
        _draftGECToRHelperEndpoint = State(initialValue: settings.gectorHelperEndpoint)
        _draftGECToRRequestTimeout = State(initialValue: settings.gectorRequestTimeout)
        _draftGeminiAPIKey = State(initialValue: settings.geminiAPIKey)
        _draftGeminiModel = State(initialValue: settings.geminiModel)
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
                Toggle("Auto-hide popup", isOn: $draftIsAutoHideEnabled)
                Stepper("Auto-hide timeout: \(Int(draftAutoHideTimeout)) seconds", value: $draftAutoHideTimeout, in: 2...30, step: 1)
                    .disabled(!draftIsAutoHideEnabled)

                Toggle("Enable shortcut checking", isOn: $draftIsManualShortcutEnabled)

                LabeledContent("Check selected text shortcut") {
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

            Section("Local GECToR Helper") {
                TextField("Endpoint", text: $draftGECToRHelperEndpoint)
                Stepper("Request timeout: \(Int(draftGECToRRequestTimeout)) seconds", value: $draftGECToRRequestTimeout, in: 1...10, step: 1)
                Text("The app starts the local helper in the background on launch and stops it on quit. LanguageTool runs first, then GECToR improves sentence-level grammar when LanguageTool + GECToR is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cloud AI with Gemini") {
                SecureField("API Key", text: $draftGeminiAPIKey)
                TextField("Model", text: $draftGeminiModel)
                Text("Gemini sends selected text to Google's API only when Cloud AI via Gemini is selected. The free tier has limits and may use submitted content to improve Google products.")
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
        .frame(width: 540, height: 580)
        .onDisappear {
            stopRecordingShortcut()
        }
        .onReceive(settings.$correctionMode.removeDuplicates()) { correctionMode in
            draftCorrectionMode = correctionMode
        }
        .onChange(of: draftCorrectionMode) { correctionMode in
            settings.correctionMode = correctionMode
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
        draftIsAutoHideEnabled = settings.isAutoHideEnabled
        draftAutoHideTimeout = settings.autoHideTimeout
        draftGECToRHelperEndpoint = settings.gectorHelperEndpoint
        draftGECToRRequestTimeout = settings.gectorRequestTimeout
        draftGeminiAPIKey = settings.geminiAPIKey
        draftGeminiModel = settings.geminiModel
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
        settings.isAutoHideEnabled = draftIsAutoHideEnabled
        settings.autoHideTimeout = draftAutoHideTimeout
        settings.gectorHelperEndpoint = draftGECToRHelperEndpoint
        settings.gectorRequestTimeout = draftGECToRRequestTimeout
        settings.geminiAPIKey = draftGeminiAPIKey
        settings.geminiModel = draftGeminiModel
        settings.isManualShortcutEnabled = draftIsManualShortcutEnabled
        settings.checkSelectionShortcut = draftCheckSelectionShortcut
    }
}
