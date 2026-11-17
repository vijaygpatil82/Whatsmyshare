import SwiftUI
import SwiftData

struct GroupDetailView: View {
    let group: ExpenseGroup
    let me: Person

    @Environment(\.modelContext) private var context

    @State private var tab: DetailTab = .activity
    @State private var showingAddExpense = false
    @State private var editingExpense: Expense?
    @State private var showingEditGroup = false
    @State private var settleUpDraft: SettleUpDraft?

    enum DetailTab: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case balances = "Balances"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                header
            }

            Section {
                Picker("View", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch tab {
            case .activity: activitySections
            case .balances: balanceSections
            }
        }
        .navigationTitle("\(group.emoji) \(group.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: group.shareSummary(me: me)) {
                    Label("Share summary", systemImage: "square.and.arrow.up")
                }
                Button("Edit group", systemImage: "person.2.badge.gearshape") {
                    showingEditGroup = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    settleUpDraft = defaultSettleUpDraft()
                } label: {
                    Label("Settle up", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled((group.members?.count ?? 0) < 2)

                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add expense", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEditorView(group: group, expense: nil, me: me)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditorView(group: group, expense: expense, me: me)
        }
        .sheet(isPresented: $showingEditGroup) {
            GroupEditorView(group: group, me: me)
        }
        .sheet(item: $settleUpDraft) { draft in
            SettleUpView(group: group, me: me, draft: draft)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total spent").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(group.totalSpentMinor, code: group.currencyCode))
                    .font(.title2.bold())
                HStack(spacing: -8) {
                    ForEach(group.sortedMembers.prefix(6)) { person in
                        Avatar(name: person.name, size: 26)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                    if (group.members?.count ?? 0) > 6 {
                        Text("+\((group.members?.count ?? 0) - 6)")
                            .font(.caption)
                            .padding(.leading, 12)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
            BalanceLabel(amountMinor: group.balance(for: me), currencyCode: group.currencyCode)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Activity

    @ViewBuilder
    private var activitySections: some View {
        let months = activityByMonth
        if months.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No expenses yet", systemImage: "receipt")
                } description: {
                    Text("Tap “Add expense” to record who paid and how to split it.")
                }
            }
        } else {
            ForEach(months, id: \.title) { month in
                Section(month.title) {
                    ForEach(month.items) { item in
                        switch item {
                        case .expense(let expense):
                            Button {
                                editingExpense = expense
                            } label: {
                                ExpenseRow(expense: expense, me: me, currencyCode: group.currencyCode)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(expense)
                                    try? context.save()
                                }
                            }
                        case .settlement(let settlement):
                            SettlementRow(settlement: settlement, currencyCode: group.currencyCode)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(settlement)
                                        try? context.save()
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var activityByMonth: [ActivityMonth] {
        var items: [ActivityItem] = (group.expenses ?? []).map { .expense($0) }
        items += (group.settlements ?? []).map { .settlement($0) }
        items.sort { $0.date > $1.date }

        var months: [ActivityMonth] = []
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        for item in items {
            let title = formatter.string(from: item.date)
            if months.last?.title == title {
                months[months.count - 1].items.append(item)
            } else {
                months.append(ActivityMonth(title: title, items: [item]))
            }
        }
        return months
    }

    // MARK: - Balances

    @ViewBuilder
    private var balanceSections: some View {
        let balances = group.balances
        Section("Balances") {
            ForEach(group.sortedMembers) { person in
                let amount = balances[person.id] ?? 0
                HStack {
                    PersonRow(name: person.name, detail: nil, isMe: person.isMe)
                    Spacer()
                    if amount > 0 {
                        Text("gets back \(Money.format(amount, code: group.currencyCode))")
                            .foregroundStyle(.green)
                    } else if amount < 0 {
                        Text("owes \(Money.format(-amount, code: group.currencyCode))")
                            .foregroundStyle(.orange)
                    } else {
                        Text("settled up").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }

        let transfers = group.suggestedTransfers
        Section {
            if transfers.isEmpty {
                Label("Everyone is settled up", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(transfer.from.displayName) → \(transfer.to.displayName)")
                            Text(Money.format(transfer.amountMinor, code: group.currencyCode))
                                .font(.headline)
                        }
                        Spacer()
                        Button("Record") {
                            settleUpDraft = SettleUpDraft(
                                payerID: transfer.from.id,
                                payeeID: transfer.to.id,
                                amountMinor: transfer.amountMinor
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            Text("Suggested payments")
        } footer: {
            Text("The fewest payments that get everyone square. Tap Record once the money has changed hands (cash, bank transfer, any app).")
        }
    }

    private func defaultSettleUpDraft() -> SettleUpDraft {
        let transfers = group.suggestedTransfers
        if let mine = transfers.first(where: { $0.from.id == me.id || $0.to.id == me.id }) {
            return SettleUpDraft(payerID: mine.from.id, payeeID: mine.to.id, amountMinor: mine.amountMinor)
        }
        let other = group.sortedMembers.first { !$0.isMe }
        return SettleUpDraft(payerID: me.id, payeeID: other?.id, amountMinor: 0)
    }
}

// MARK: - Supporting types

enum ActivityItem: Identifiable {
    case expense(Expense)
    case settlement(Settlement)

    var id: String {
        switch self {
        case .expense(let e): return "e-\(e.id.uuidString)"
        case .settlement(let s): return "s-\(s.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .settlement(let s): return s.date
        }
    }
}

struct ActivityMonth {
    var title: String
    var items: [ActivityItem]
}

struct ExpenseRow: View {
    let expense: Expense
    let me: Person
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.symbol)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.body.weight(.medium))
                Text("\(expense.paidBy?.displayName ?? "Someone") paid \(Money.format(expense.amountMinor, code: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(expense.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            involvement
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var involvement: some View {
        let myShare = expense.share(for: me)
        let iPaid = expense.paidBy?.id == me.id
        VStack(alignment: .trailing, spacing: 2) {
            if iPaid, expense.amountMinor - myShare > 0 {
                Text("you lent").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(expense.amountMinor - myShare, code: currencyCode))
                    .font(.subheadline.bold()).foregroundStyle(.green)
            } else if iPaid {
                Text("just you").font(.caption).foregroundStyle(.secondary)
            } else if myShare > 0 {
                Text("you borrowed").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(myShare, code: currencyCode))
                    .font(.subheadline.bold()).foregroundStyle(.orange)
            } else {
                Text("not involved").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettlementRow: View {
    let settlement: Settlement
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(settlement.payer?.displayName ?? "Someone") paid \(settlement.payee?.displayName ?? "someone")")
                    .font(.body.weight(.medium))
                Text(settlement.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Money.format(settlement.amountMinor, code: currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(.green)
        }
    }
}
