import SwiftUI

struct AccessibilityPermissionView: View {
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text("Accessibility Permission Required")
                    .font(.title2.weight(.semibold))
            }

            Text("Spelling Popup Assistant requires Accessibility permission to read selected text and replace it when requested.")
                .foregroundStyle(.primary)

            Text("Open System Settings > Privacy & Security > Accessibility, then enable Spelling Popup Assistant.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Accessibility Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                Button("Check Again", action: onRecheck)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 520, height: 300, alignment: .leading)
    }
}
