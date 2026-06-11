import AppKit

struct ClipboardSnapshot {
    let string: String?
}

final class ClipboardService {
    static let shared = ClipboardService()

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(string: pasteboard.string(forType: .string))
    }

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        if let string = snapshot.string {
            pasteboard.setString(string, forType: .string)
        }
    }
}
