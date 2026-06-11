import SwiftUI

struct CorrectionPopupView: View {
    @ObservedObject private var settings = AppSettings.shared

    let result: CorrectionResult
    let transientMessage: String?
    let onReplace: () -> Void
    let onCopy: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spelling Correction")
                    .font(.headline)
                Spacer()
                Text("\(settings.grammarCheckerEnabled ? "Issues" : "Misspelled words"): \(result.misspelledWordCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(result.correctedText)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.corrections.prefix(5)) { correction in
                        HStack(spacing: 6) {
                            Text(correction.original)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(correction.corrected)
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }
                }
            }

            if let transientMessage {
                Text(transientMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Replace", action: onReplace)
                    .buttonStyle(.borderedProminent)
                Button("Copy", action: onCopy)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Ignore", action: onIgnore)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
