import SwiftUI
import SwiftData

/// Pre-filled values for the settle-up sheet.
struct SettleUpDraft: Identifiable {
    let id = UUID()
    var payerID: UUID?
    var payeeID: UUID?
    var amountMinor: Int
}

/// Record a repayment between two members ("Bob paid Alice $20").
struct SettleUpView: View {
    let group: ExpenseGroup
    let me: Person
    let draft: SettleUpDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var payerID: UUID?
    @State private var payeeID: UUID?
    @State private var amountText = ""
    @State private var date = Date()
    @State private var loaded = false

    private var code: String { group.currencyCode }
    private var members: [Person] { group.sortedMembers }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who paid", selection: $payerID) {
                        ForEach(members) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("Who received", selection: $payeeID) {
                        ForEach(members) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                } footer: {
                    if let owed = currentDebt, owed > 0 {
                        Text("Currently owed between them: \(Money.format(owed, code: code))")
                    }
                }

                Section("Amount") {
                    HStack {
                        Text(Money.symbol(for: code)).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    Text("This just records that the money changed hands — by cash, bank transfer or any payment app. No money is moved by What's My Share.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    /// How much the payer owes the payee according to suggested payments.
    private var currentDebt: Int? {
        guard let payerID, let payeeID else { return nil }
        return group.suggestedTransfers
            .first { $0.from.id == payerID && $0.to.id == payeeID }?
            .amountMinor
    }

    private var amountMinor: Int? {
        guard let minor = Money.parseMinor(amountText, code: code), minor > 0 else { return nil }
        return minor
    }

    private var canSave: Bool {
        payerID != nil && payeeID != nil && payerID != payeeID && amountMinor != nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        payerID = draft.payerID ?? me.id
        payeeID = draft.payeeID ?? members.first { $0.id != payerID }?.id
        if draft.amountMinor > 0 {
            amountText = Money.editingString(draft.amountMinor, code: code)
        }
    }

    private func save() {
        guard canSave,
              let amount = amountMinor,
              let payer = members.first(where: { $0.id == payerID }),
              let payee = members.first(where: { $0.id == payeeID }) else { return }
        let settlement = Settlement(amountMinor: amount, date: date)
        context.insert(settlement)
        settlement.payer = payer
        settlement.payee = payee
        settlement.group = group
        try? context.save()
        dismiss()
    }
}
