import Foundation
import os

enum Logger {
    static let app = os.Logger(subsystem: "SpellingPopupAssistant", category: "App")
    static let accessibility = os.Logger(subsystem: "SpellingPopupAssistant", category: "Accessibility")
    static let correction = os.Logger(subsystem: "SpellingPopupAssistant", category: "Correction")
}
