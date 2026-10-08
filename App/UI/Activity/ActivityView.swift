import DeclutterCore
import SwiftUI

struct ActivityView: View {
    @Bindable var model: ActivityViewModel
    var searchFocus: Int
    @FocusState private var searchFocused: Bool

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 360)
            inspector
                .frame(minWidth: 280, idealWidth: 340)
        }
        .navigationTitle("Activity")
        .task { await model.reload() }
        .onChange(of: searchFocus) { _, _ in
            searchFocused = true
        }
        .alert(
            "Could Not Load History",
            isPresented: Binding(
                get: { model.errorText != nil },
                set: { isPresented in
                    if !isPresented { model.errorText = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            stats
            filters
            if let report = model.reportText {
                Text(report)
                    .font(.callout)
                    .accessibilityLabel(report)
            }
            if model.days.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("Organize files and each move shows up here, grouped by day.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.days) { day in
                        Section(day.title) {
                            ForEach(day.items) { item in
                                row(item)
                                    .tag(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .accessibilityLabel("History grouped by day")
            }
        }
        .padding(12)
    }

    private var stats: some View {
        HStack(spacing: 8) {
            statPill(label: "Total Organized", count: model.stats.totalOrganized, color: .purple)
            statPill(label: "Today", count: model.stats.organizedToday, color: .blue)
            statPill(label: "Skipped", count: model.stats.skipped, color: .secondary)
            if model.stats.failed > 0 {
                statPill(label: "Failed", count: model.stats.failed, color: .red)
            }
            Spacer()
        }
    }

    private func statPill(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
    }

    private var filters: some View {
        HStack {
            TextField("Search history", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search history")
            Picker("Status", selection: $model.statusFilter) {
                Text("Any status").tag(OperationStatus?.none)
                ForEach(OperationStatus.allCases, id: \.self) { status in
                    Text(ActivityFormatting.status(status)).tag(Optional(status))
                }
            }
            .frame(maxWidth: 180)
            Picker("Category", selection: $model.categoryFilter) {
                Text("All categories").tag("")
                ForEach(model.categories, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(maxWidth: 180)
            Picker("When", selection: $model.range) {
                ForEach(ActivityRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .frame(maxWidth: 160)
        }
    }

    private func row(_ item: HistoryItem) -> some View {
        HStack {
            Image(systemName: ActivityFormatting.symbol(item.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.originalName)
                Text("\(ActivityFormatting.status(item.status)) · \(item.categoryName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.originalName), \(ActivityFormatting.status(item.status)), \(item.categoryName)")
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = model.selected {
                Text(item.originalName)
                    .font(.title3)
                LabeledContent("Status", value: ActivityFormatting.status(item.status))
                LabeledContent("Category", value: item.categoryName)
                LabeledContent("Destination", value: item.finalName)
                Text(item.ruleSummary)
                    .font(.callout)
                if !item.message.isEmpty {
                    Text(item.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(item.sourcePath)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(item.destinationPath)
                    .font(.caption)
                    .textSelection(.enabled)
                Button("Undo") {
                    Task { await model.undoSelected() }
                }
                .disabled(!(item.undoable && item.status == .success))
                .accessibilityHint("Moves this file back. If the original name is taken, it is restored beside it.")
                Spacer()
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a move to see why it happened and to undo it.")
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

enum ActivityFormatting {
    static func status(_ status: OperationStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .success: "Organized"
        case .skipped: "Skipped"
        case .failed: "Failed"
        case .undone: "Undone"
        case .needsDecision: "Needs a decision"
        }
    }

    static func symbol(_ status: OperationStatus) -> String {
        switch status {
        case .pending: "clock"
        case .success: "checkmark.circle"
        case .skipped: "minus.circle"
        case .failed: "xmark.circle"
        case .undone: "arrow.uturn.backward.circle"
        case .needsDecision: "questionmark.circle"
        }
    }
}
