import DeclutterCore
import SwiftUI

struct RuleNodeEditor: View {
    @Binding var node: RuleNode
    var onDelete: () -> Void

    var body: some View {
        Group {
            if case .group = node {
                groupEditor
            } else {
                conditionEditor
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Match", selection: opBinding) {
                    Text("All").tag(LogicalOp.and)
                    Text("Any").tag(LogicalOp.or)
                    Text("None").tag(LogicalOp.not)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Match all, any, or none of the conditions in this group")
                Button("Remove Group", systemImage: "trash", action: onDelete)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Remove group")
            }
            if children.isEmpty {
                Text(emptyGroupText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(children.indices), id: \.self) { index in
                RuleNodeEditor(node: childBinding(index), onDelete: { deleteChild(index) })
            }
            HStack {
                Button("Add Condition", systemImage: "plus") { add(condition: true) }
                Button("Add Group", systemImage: "plus.rectangle") { add(condition: false) }
            }
            .buttonStyle(.borderless)
        }
    }

    private var conditionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Picker("Field", selection: fieldBinding) {
                    ForEach(Field.editorOrder, id: \.self) { field in
                        Text(RuleLabels.field(field)).tag(field)
                    }
                }
                .accessibilityLabel("Condition field")
                Picker("Operator", selection: operatorBinding) {
                    ForEach(condition.field.supportedOperators, id: \.self) { op in
                        Text(RuleLabels.op(op, field: condition.field)).tag(op)
                    }
                }
                .accessibilityLabel("Condition operator")
                Spacer()
                Button("Remove Condition", systemImage: "trash", action: onDelete)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Remove condition")
            }
            valueEditor
            if showsMatchCase {
                Toggle("Match case", isOn: matchCaseBinding)
                    .accessibilityHint("Off compares letters without regard to case.")
            }
            if condition.field == .filename, condition.op == .regex, let message = RuleValidator.regexError(pattern: condition.value ?? "") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid regular expression. \(message)")
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch condition.op {
        case .isOneOf:
            TextField("pdf, png", text: listBinding)
                .accessibilityLabel("Values, separated by commas")
        case .between where condition.field == .size:
            HStack {
                TextField("Minimum bytes", text: boundBinding(0))
                Text("and")
                TextField("Maximum bytes", text: boundBinding(1))
            }
        case .between:
            HStack {
                DatePicker("Start", selection: dateBoundBinding(0), displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: dateBoundBinding(1), displayedComponents: [.date, .hourAndMinute])
            }
        case .before, .after:
            DatePicker("Date", selection: singleDateBinding, displayedComponents: [.date, .hourAndMinute])
        case .greaterThan, .lessThan, .equals:
            TextField(condition.field == .size ? "Bytes" : valuePrompt, text: valueBinding)
                .accessibilityLabel(condition.field == .size ? "Size in bytes" : "Condition value")
        default:
            TextField(valuePrompt, text: valueBinding)
                .accessibilityLabel("Condition value")
        }
    }

    private var condition: Condition {
        if case .condition(let condition) = node { return condition }
        return Condition(field: .filename, op: .contains, value: "")
    }

    private var children: [RuleNode] {
        if case .group(_, let children) = node { return children }
        return []
    }

    private var showsMatchCase: Bool {
        switch condition.field {
        case .extension_, .filename, .fileType:
            true
        case .size, .createdDate, .modifiedDate:
            false
        }
    }

    private var emptyGroupText: String {
        switch opBinding.wrappedValue {
        case .and:
            "An empty All group matches every file."
        case .or:
            "An empty Any group matches nothing."
        case .not:
            "An empty None group matches every file."
        }
    }

    private var valuePrompt: String {
        switch condition.field {
        case .extension_:
            "pdf"
        case .filename:
            condition.op == .regex ? "invoice-\\d+" : "invoice"
        case .fileType:
            "public.image"
        default:
            "Value"
        }
    }

    private var opBinding: Binding<LogicalOp> {
        Binding(
            get: {
                if case .group(let op, _) = node { return op }
                return .and
            },
            set: { newOp in
                guard case .group(_, let children) = node else { return }
                node = .group(newOp, children)
            }
        )
    }

    private var fieldBinding: Binding<Field> {
        Binding(
            get: { condition.field },
            set: { newField in
                var updated = condition
                updated.field = newField
                if !newField.supportedOperators.contains(updated.op) {
                    updated.op = newField.supportedOperators[0]
                }
                node = .condition(updated)
            }
        )
    }

    private var operatorBinding: Binding<Operator> {
        Binding(
            get: { condition.op },
            set: { newOp in
                var updated = condition
                updated.op = newOp
                node = .condition(updated)
            }
        )
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { condition.value ?? "" },
            set: { newValue in
                var updated = condition
                updated.value = newValue
                node = .condition(updated)
            }
        )
    }

    private var listBinding: Binding<String> {
        Binding(
            get: { condition.values.joined(separator: ", ") },
            set: { newValue in
                var updated = condition
                updated.values = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                node = .condition(updated)
            }
        )
    }

    private var matchCaseBinding: Binding<Bool> {
        Binding(
            get: { condition.matchCase },
            set: { newValue in
                var updated = condition
                updated.matchCase = newValue
                node = .condition(updated)
            }
        )
    }

    private var singleDateBinding: Binding<Date> {
        Binding(
            get: { RuleValueParsing.date(from: condition.value) ?? Date() },
            set: { newDate in
                var updated = condition
                updated.value = RuleValueParsing.format(date: newDate)
                node = .condition(updated)
            }
        )
    }

    private func boundBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                condition.values.indices.contains(index) ? condition.values[index] : ""
            },
            set: { newValue in
                var updated = condition
                var values = updated.values
                while values.count <= index { values.append("") }
                values[index] = newValue
                updated.values = values
                node = .condition(updated)
            }
        )
    }

    private func dateBoundBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let raw = condition.values.indices.contains(index) ? condition.values[index] : nil
                return RuleValueParsing.date(from: raw) ?? Date()
            },
            set: { newDate in
                var updated = condition
                var values = updated.values
                while values.count <= index { values.append("") }
                values[index] = RuleValueParsing.format(date: newDate)
                updated.values = values
                node = .condition(updated)
            }
        )
    }

    private func childBinding(_ index: Int) -> Binding<RuleNode> {
        Binding(
            get: {
                children.indices.contains(index) ? children[index] : .group(.and, [])
            },
            set: { newValue in
                guard case .group(let op, var children) = node, children.indices.contains(index) else { return }
                children[index] = newValue
                node = .group(op, children)
            }
        )
    }

    private func deleteChild(_ index: Int) {
        guard case .group(let op, var children) = node, children.indices.contains(index) else { return }
        children.remove(at: index)
        node = .group(op, children)
    }

    private func add(condition: Bool) {
        guard case .group(let op, var children) = node else { return }
        if condition {
            children.append(.condition(Condition(field: .filename, op: .contains, value: "")))
        } else {
            children.append(.group(.and, [.condition(Condition(field: .filename, op: .contains, value: ""))]))
        }
        node = .group(op, children)
    }
}

private enum RuleLabels {
    static func field(_ field: Field) -> String {
        switch field {
        case .extension_: "Extension"
        case .filename: "Filename"
        case .fileType: "File type"
        case .size: "Size"
        case .createdDate: "Created"
        case .modifiedDate: "Modified"
        }
    }

    static func op(_ op: Operator, field: Field) -> String {
        switch op {
        case .is: "is"
        case .isNot: "is not"
        case .isOneOf: "is one of"
        case .contains: "contains"
        case .notContains: "does not contain"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        case .equals: field == .size ? "equal" : "equals"
        case .notEquals: "does not equal"
        case .regex: "matches regex"
        case .conformsTo: "conforms to"
        case .greaterThan: "greater than"
        case .lessThan: "less than"
        case .between: "between"
        case .before: "before"
        case .after: "after"
        }
    }
}

private extension Field {
    static let editorOrder: [Field] = [.extension_, .filename, .fileType, .size, .createdDate, .modifiedDate]
}
