import SwiftUI
import SwiftData

struct GroupsListView: View {
    let me: Person

    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseGroup.createdAt, order: .reverse) private var groups: [ExpenseGroup]

    @State private var showingNewGroup = false
    @State private var showingSettings = false
    @State private var groupToDelete: ExpenseGroup?

    var body: some View {
        NavigationStack {
            List {
                if !groups.isEmpty {
                    Section {
                        OverallSummaryView(groups: groups, me: me)
                    }
                }
                Section(groups.isEmpty ? "" : "Groups") {
                    ForEach(groups) { group in
                        NavigationLink(value: group) {
                            GroupRow(group: group, me: me)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                groupToDelete = group
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationDestination(for: ExpenseGroup.self) { group in
                GroupDetailView(group: group, me: me)
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No groups yet", systemImage: "person.3")
                    } description: {
                        Text("Create a group for a trip, your household or a night out, then add people from your contacts.")
                    } actions: {
                        Button("Create a group") { showingNewGroup = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Group", systemImage: "plus") { showingNewGroup = true }
                }
            }
            .sheet(isPresented: $showingNewGroup) {
                GroupEditorView(group: nil, me: me)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(me: me)
            }
            .confirmationDialog(
                "Delete \(groupToDelete?.name ?? "group")?",
                isPresented: Binding(get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Group", role: .destructive) {
                    if let group = groupToDelete {
                        context.delete(group)
                        try? context.save()
                    }
                    groupToDelete = nil
                }
            } message: {
                Text("All of its expenses and payments will be removed. This can't be undone.")
            }
        }
    }
}

private struct GroupRow: View {
    let group: ExpenseGroup
    let me: Person

    var body: some View {
        let balance = group.balance(for: me)
        HStack(spacing: 12) {
            Text(group.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text("\(group.members?.count ?? 0) people")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BalanceLabel(amountMinor: balance, currencyCode: group.currencyCode)
        }
        .padding(.vertical, 2)
    }
}

/// "you are owed $X" / "you owe $X" / "settled up", coloured.
struct BalanceLabel: View {
    let amountMinor: Int
    let currencyCode: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if amountMinor > 0 {
                Text("you are owed").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(amountMinor, code: currencyCode)).font(.subheadline.bold()).foregroundStyle(.green)
            } else if amountMinor < 0 {
                Text("you owe").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(-amountMinor, code: currencyCode)).font(.subheadline.bold()).foregroundStyle(.orange)
            } else {
                Text("settled up").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Totals across all groups, per currency.
private struct OverallSummaryView: View {
    let groups: [ExpenseGroup]
    let me: Person

    var body: some View {
        let totals = perCurrencyTotals
        VStack(alignment: .leading, spacing: 6) {
            Text("Overall").font(.caption).foregroundStyle(.secondary)
            if totals.allSatisfy({ $0.owed == 0 && $0.owe == 0 }) {
                Label("You're all settled up", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                ForEach(totals) { total in
                    if total.owed > 0 {
                        Text("You are owed \(Money.format(total.owed, code: total.code))")
                            .font(.headline).foregroundStyle(.green)
                    }
                    if total.owe > 0 {
                        Text("You owe \(Money.format(total.owe, code: total.code))")
                            .font(.headline).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private struct CurrencyTotal: Identifiable {
        var code: String
        var owed: Int
        var owe: Int
        var id: String { code }
    }

    private var perCurrencyTotals: [CurrencyTotal] {
        var owed: [String: Int] = [:]
        var owe: [String: Int] = [:]
        for group in groups {
            let b = group.balance(for: me)
            if b > 0 { owed[group.currencyCode, default: 0] += b }
            if b < 0 { owe[group.currencyCode, default: 0] += -b }
        }
        let codes = Set(owed.keys).union(owe.keys).sorted()
        return codes.map { CurrencyTotal(code: $0, owed: owed[$0] ?? 0, owe: owe[$0] ?? 0) }
    }
}
