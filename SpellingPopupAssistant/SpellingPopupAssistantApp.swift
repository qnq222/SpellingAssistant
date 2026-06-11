import SwiftUI

@main
struct SpellingPopupAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: .shared)
        }
    }
}
