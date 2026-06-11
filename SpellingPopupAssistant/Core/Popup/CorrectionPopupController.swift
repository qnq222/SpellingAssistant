import AppKit
import SwiftUI

@MainActor
final class CorrectionPopupController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private let positioningService = PopupPositioningService()
    private let clipboardService: ClipboardService
    private let replacementService: TextReplacementService
    private let settings: AppSettings

    init(
        clipboardService: ClipboardService = .shared,
        replacementService: TextReplacementService = TextReplacementService(),
        settings: AppSettings = .shared
    ) {
        self.clipboardService = clipboardService
        self.replacementService = replacementService
        self.settings = settings
    }

    func show(result: CorrectionResult, transientMessage: String? = nil) {
        hideTask?.cancel()

        let view = CorrectionPopupView(
            result: result,
            transientMessage: transientMessage,
            onReplace: { [weak self] in
                Task { @MainActor in
                    await self?.replace(result.correctedText)
                }
            },
            onCopy: { [weak self] in
                self?.copy(result.correctedText)
            },
            onIgnore: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(width: min(max(fittingSize.width, 320), 460), height: min(max(fittingSize.height, 180), 420))
        let frame = positioningService.frameNearMouse(size: panelSize)

        let panel = panel ?? makePanel()
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        scheduleAutoHide()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    private func copy(_ text: String) {
        clipboardService.copy(text)
        scheduleAutoHide(short: true)
    }

    private func replace(_ text: String) async {
        do {
            try await replacementService.replaceSelection(with: text)
            hide()
        } catch {
            clipboardService.copy(text)
            scheduleAutoHide(short: true)
        }
    }

    private func scheduleAutoHide(short: Bool = false) {
        hideTask?.cancel()
        let seconds = short ? 1.2 : settings.autoHideTimeout
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hide()
            }
        }
    }
}
