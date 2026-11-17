import SwiftUI
import SwiftData

/// Add a new expense or edit an existing one.
struct ExpenseEditorView: View {
    let group: ExpenseGroup
    /// nil when adding.
    let expense: Expense?
    let me: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var category: ExpenseCategory = .general
    @State private var notes = ""
    @State private var payerID: UUID?
    @State private var method: SplitMethod = .equal
    @State private var included: Set<UUID> = []
    /// Per-person typed values for exact / percentage / shares.
    @State private var values: [UUID: String] = [:]
    @State private var loaded = false
    @State private var confirmingDelete = false

    @FocusState private var amountFocused: Bool

    private var members: [Person] { group.sortedMembers }
    private var code: String { group.currencyCode }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                        .textInputAutocapitalization(.sentences)
                    HStack {
                        Text(Money.symbol(for: code))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                            .focused($amountFocused)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                }

                Section("Paid by") {
                    Picker("Paid by", selection: $payerID) {
                        ForEach(members) { person in
                            Text(person.displayName).tag(Optional(person.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Section {
                    // Prefill sensible values only when the user switches method
                    // (not when an existing expense is loaded).
                    Picker("Split", selection: Binding(
                        get: { method },
                        set: { newMethod in
                            guard newMethod != method else { return }
                            method = newMethod
                            prefillValues(for: newMethod)
                        }
                    )) {
                        ForEach(SplitMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(members) { person in
                        splitRow(for: person)
                    }
                } header: {
                    Text("Split")
                } footer: {
                    splitStatus
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if expense != nil {
                    Section {
                        Button("Delete expense", role: .destructive) {
                            confirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteExpense)
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Split rows

    @ViewBuilder
    private func splitRow(for person: Person) -> some View {
        let isIncluded = included.contains(person.id)
        let preview = (try? computeSplit().get())?[person.id]
        HStack(spacing: 10) {
            Button {
                toggle(person)
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIncluded ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncluded ? "Remove \(person.displayName) from split" : "Add \(person.displayName) to split")

            Text(person.displayName)
                .foregroundStyle(isIncluded ? Color.primary : Color.secondary)

            Spacer()

            if isIncluded && method != .equal {
                TextField(placeholder, text: valueBinding(for: person))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                if method == .percentage {
                    Text("%").foregroundStyle(.secondary)
                }
            }

            if isIncluded, method != .exact {
                Text(preview.map { Money.format($0, code: code) } ?? "–")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
    }

    private var placeholder: String {
        switch method {
        case .equal: return ""
        case .exact: return "0.00"
        case .percentage: return "0"
        case .shares: return "1"
        }
    }

    @ViewBuilder
    private var splitStatus: some View {
        switch computeSplit() {
        case .success:
            if amountMinor != nil {
                Label("Adds up", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case .failure(let error):
            Text(message(for: error))
                .foregroundStyle(.orange)
        }
    }

    private func message(for error: SplitError) -> String {
        switch error {
        case .noParticipants:
            return "Pick at least one person to split with."
        case .invalidTotal:
            return "Enter the amount."
        case .negativeValue:
            return "Amounts can't be negative."
        case .exactMismatch(let difference):
            let amount = Money.format(abs(difference), code: code)
            return difference < 0 ? "\(amount) still to assign." : "\(amount) too much assigned."
        case .percentageMismatch(let total):
            let rounded = (total * 100).rounded() / 100
            return "Percentages add up to \(rounded.formatted())%, not 100%."
        case .zeroShares:
            return "Give at least one person a share."
        }
    }

    // MARK: - Calculation

    private var amountMinor: Int? {
        guard let minor = Money.parseMinor(amountText, code: code), minor > 0 else { return nil }
        return minor
    }

    private var participants: [UUID] {
        members.map(\.id).filter { included.contains($0) }
    }

    /// Numeric value per person, in the units SplitCalculator expects.
    private var numericValues: [UUID: Double] {
        var result: [UUID: Double] = [:]
        for id in participants {
            let text = values[id] ?? ""
            switch method {
            case .equal:
                break
            case .exact:
                result[id] = Double(Money.parseMinor(text, code: code) ?? 0)
            case .percentage, .shares:
                if let d = Money.parseDecimal(text) {
                    result[id] = NSDecimalNumber(decimal: d).doubleValue
                } else {
                    result[id] = 0
                }
            }
        }
        return result
    }

    private func computeSplit() -> Result<[UUID: Int], SplitError> {
        guard let total = amountMinor else { return .failure(.invalidTotal) }
        do {
            let split = try SplitCalculator.split(
                totalMinor: total, method: method, participants: participants, values: numericValues
            )
            return .success(split)
        } catch let error as SplitError {
            return .failure(error)
        } catch {
            return .failure(.invalidTotal)
        }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, payerID != nil else { return false }
        if case .success = computeSplit() { return true }
        return false
    }

    // MARK: - Actions

    private func valueBinding(for person: Person) -> Binding<String> {
        Binding(
            get: { values[person.id] ?? "" },
            set: { values[person.id] = $0 }
        )
    }

    private func toggle(_ person: Person) {
        if included.contains(person.id) {
            included.remove(person.id)
        } else {
            included.insert(person.id)
            if method == .shares, (values[person.id] ?? "").isEmpty {
                values[person.id] = "1"
            }
        }
    }

    private func prefillValues(for newMethod: SplitMethod) {
        values = [:]
        let ids = participants
        guard !ids.isEmpty else { return }
        switch newMethod {
        case .equal:
            break
        case .shares:
            for id in ids { values[id] = "1" }
        case .percentage:
            // Start from an even split the user can adjust.
            let even = (10000 / ids.count)   // hundredths of a percent
            var remaining = 10000
            for (index, id) in ids.enumerated() {
                let part = index == ids.count - 1 ? remaining : even
                remaining -= part
                values[id] = (Double(part) / 100).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
        case .exact:
            if let total = amountMinor,
               let split = try? SplitCalculator.split(totalMinor: total, method: .equal, participants: ids) {
                for id in ids { values[id] = Money.editingString(split[id] ?? 0, code: code) }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let expense {
            title = expense.title
            amountText = Money.editingString(expense.amountMinor, code: code)
            date = expense.date
            category = expense.category
            notes = expense.notes
            payerID = expense.paidBy?.id
            method = expense.splitMethod
            var newValues: [UUID: String] = [:]
            var newIncluded: Set<UUID> = []
            for share in expense.shares ?? [] {
                guard let person = share.person else { continue }
                newIncluded.insert(person.id)
                switch expense.splitMethod {
                case .equal:
                    break
                case .exact:
                    newValues[person.id] = Money.editingString(share.amountMinor, code: code)
                case .percentage, .shares:
                    newValues[person.id] = share.inputValue.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
                }
            }
            included = newIncluded
            values = newValues
        } else {
            payerID = me.id
            included = Set(members.map(\.id))
            amountFocused = true
        }
    }

    private func save() {
        guard case .success(let split) = computeSplit(),
              let total = amountMinor,
              let payer = members.first(where: { $0.id == payerID }) else { return }

        let target: Expense
        if let expense {
            target = expense
            for share in expense.shares ?? [] {
                context.delete(share)
            }
            target.shares = []
        } else {
            target = Expense(title: "", amountMinor: total, date: date)
            context.insert(target)
            target.group = group
        }

        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.amountMinor = total
        target.date = date
        target.notes = notes
        target.category = category
        target.splitMethod = method
        target.paidBy = payer

        let typed = numericValues
        for person in members {
            guard let amount = split[person.id] else { continue }
            let share = ExpenseShare(amountMinor: amount, inputValue: typed[person.id] ?? 0)
            context.insert(share)
            share.person = person
            share.expense = target
        }

        try? context.save()
        dismiss()
    }

    private func deleteExpense() {
        if let expense {
            context.delete(expense)
            try? context.save()
        }
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
