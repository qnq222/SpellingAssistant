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
                Text("Writing Check")
                    .font(.headline)
                Spacer()
                Text("Total Issues: \(result.totalIssueCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Grammar Issues: \(result.grammarIssueCount)")
                Text("Spelling Issues: \(result.spellingIssueCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(result.correctedText)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.issues.isEmpty || !result.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Issue Details")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(displayIssues.prefix(6)) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(issue.original)
                                    .strikethrough(issue.replacement != nil)
                                    .foregroundStyle(.secondary)
                                if let replacement = issue.replacement {
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(replacement)
                                        .fontWeight(.medium)
                                }
                            }
                            Text(issue.message)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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

    private var displayIssues: [CorrectionIssue] {
        if !result.issues.isEmpty {
            return result.issues
        }

        return result.corrections.map {
            CorrectionIssue(
                kind: .spelling,
                original: $0.original,
                replacement: $0.corrected,
                message: "Spelling"
            )
        }
    }
}
