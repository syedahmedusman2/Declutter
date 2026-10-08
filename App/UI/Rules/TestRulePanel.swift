import DownloadOrganizerCore
import SwiftUI

struct TestRulePanel: View {
    @Bindable var editor: CategoryEditorModel
    var model: RulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Rule")
                .font(.headline)
            Text(editor.matchCountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(editor.matchCountText)
            Button("Choose File…") {
                model.chooseTestFile()
            }
            .accessibilityHint("Shows whether this rule matches the file. The file is not moved.")
            dropArea
            if let testError = editor.testError {
                Label(testError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let report = editor.testReport {
                reportView(report)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropArea: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .accessibilityHidden(true)
            Text(editor.testFileName ?? "Drop a file here")
                .font(.callout)
            Text("Nothing is moved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(.secondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(editor.testFileName.map { "Test file \($0). Drop another file to replace it." } ?? "Drop a file to test this rule")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await model.testFile(at: url) }
            return true
        }
    }

    private func reportView(_ report: RuleTestReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(report.matched ? "MATCH" : "NO MATCH", systemImage: report.matched ? "checkmark.circle" : "xmark.circle")
                .font(.title3.weight(.semibold))
                .accessibilityLabel(report.matched ? "Match" : "No match")
            if let winner = report.higherPriorityWinnerName {
                Label("\(winner) would win instead.", systemImage: "arrow.up.circle")
                    .accessibilityLabel("A higher-priority category would win instead: \(winner)")
            } else if report.applies {
                Text("This category would be used.")
                    .foregroundStyle(.secondary)
            } else if !editor.enabled {
                Text("This category is disabled.")
                    .foregroundStyle(.secondary)
            }
            Text("Destination: \(report.destinationURL.path(percentEncoded: false))")
                .font(.caption)
                .textSelection(.enabled)
            RuleResultTree(result: report.result)
            if !report.higherPriority.isEmpty {
                DisclosureGroup("Higher-priority categories") {
                    ForEach(report.higherPriority) { considered in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(considered.name)
                                .font(.subheadline.weight(.semibold))
                            RuleResultTree(result: considered.result)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

struct RuleResultTree: View {
    var result: RuleResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: result.passed ? "checkmark" : "xmark")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.passed ? "Pass" : "Fail"): \(result.description)")
                    if result.kind == .condition {
                        Text("Actual: \(result.actualValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let warning = result.warning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(Array(result.children.enumerated()), id: \.offset) { _, child in
                RuleResultTree(result: child)
                    .padding(.leading, 16)
            }
        }
    }
}
