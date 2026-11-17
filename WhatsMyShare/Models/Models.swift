import Foundation
import SwiftData

// Everything is stored on-device with SwiftData.
// Every property has a default and every relationship is optional with an
// inverse, which keeps the door open to turning on iCloud sync later.

@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    /// `CNContact.identifier` when the person was picked from Contacts.
    var contactIdentifier: String?
    /// Phone number or email, shown as a subtitle only.
    var detail: String?
    /// The owner of the device.
    var isMe: Bool = false
    var createdAt: Date = Date()

    var groups: [ExpenseGroup]? = []
    @Relationship(deleteRule: .nullify, inverse: \Expense.paidBy)
    var paidExpenses: [Expense]? = []
    @Relationship(deleteRule: .nullify, inverse: \ExpenseShare.person)
    var shares: [ExpenseShare]? = []
    @Relationship(deleteRule: .nullify, inverse: \Settlement.payer)
    var settlementsPaid: [Settlement]? = []
    @Relationship(deleteRule: .nullify, inverse: \Settlement.payee)
    var settlementsReceived: [Settlement]? = []

    init(name: String, contactIdentifier: String? = nil, detail: String? = nil, isMe: Bool = false) {
        self.id = UUID()
        self.name = name
        self.contactIdentifier = contactIdentifier
        self.detail = detail
        self.isMe = isMe
        self.createdAt = Date()
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// "You" for the device owner, otherwise the name.
    var displayName: String { isMe ? "You" : name }
}

@Model
final class ExpenseGroup {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "👥"
    var currencyCode: String = "USD"
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Person.groups)
    var members: [Person]? = []
    @Relationship(deleteRule: .cascade, inverse: \Expense.group)
    var expenses: [Expense]? = []
    @Relationship(deleteRule: .cascade, inverse: \Settlement.group)
    var settlements: [Settlement]? = []

    init(name: String, emoji: String, currencyCode: String) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.currencyCode = currencyCode
        self.createdAt = Date()
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var title: String = ""
    var amountMinor: Int = 0
    var date: Date = Date()
    var notes: String = ""
    var categoryRaw: String = ExpenseCategory.general.rawValue
    var splitMethodRaw: String = SplitMethod.equal.rawValue
    var createdAt: Date = Date()

    var paidBy: Person?
    var group: ExpenseGroup?
    @Relationship(deleteRule: .cascade, inverse: \ExpenseShare.expense)
    var shares: [ExpenseShare]? = []

    init(title: String, amountMinor: Int, date: Date) {
        self.id = UUID()
        self.title = title
        self.amountMinor = amountMinor
        self.date = date
        self.createdAt = Date()
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }

    var splitMethod: SplitMethod {
        get { SplitMethod(rawValue: splitMethodRaw) ?? .equal }
        set { splitMethodRaw = newValue.rawValue }
    }

    func share(for person: Person) -> Int {
        (shares ?? []).filter { $0.person?.id == person.id }.reduce(0) { $0 + $1.amountMinor }
    }

    func involves(_ person: Person) -> Bool {
        paidBy?.id == person.id || (shares ?? []).contains { $0.person?.id == person.id && $0.amountMinor > 0 }
    }
}

@Model
final class ExpenseShare {
    var amountMinor: Int = 0
    /// What the user typed (exact amount in minor units, percent or share
    /// count), so the split can be edited later exactly as entered.
    var inputValue: Double = 0
    var person: Person?
    var expense: Expense?

    init(amountMinor: Int, inputValue: Double) {
        self.amountMinor = amountMinor
        self.inputValue = inputValue
    }
}

/// A repayment between two group members ("Bob paid Alice back").
@Model
final class Settlement {
    var id: UUID = UUID()
    var amountMinor: Int = 0
    var date: Date = Date()
    var payer: Person?
    var payee: Person?
    var group: ExpenseGroup?

    init(amountMinor: Int, date: Date) {
        self.id = UUID()
        self.amountMinor = amountMinor
        self.date = date
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case general, food, groceries, transport, travel, lodging, entertainment, shopping, utilities, rent, gifts, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .food: return "Food & Drink"
        case .groceries: return "Groceries"
        case .transport: return "Transport"
        case .travel: return "Travel"
        case .lodging: return "Lodging"
        case .entertainment: return "Entertainment"
        case .shopping: return "Shopping"
        case .utilities: return "Utilities"
        case .rent: return "Rent"
        case .gifts: return "Gifts"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "receipt"
        case .food: return "fork.knife"
        case .groceries: return "cart"
        case .transport: return "car"
        case .travel: return "airplane"
        case .lodging: return "bed.double"
        case .entertainment: return "ticket"
        case .shopping: return "bag"
        case .utilities: return "bolt"
        case .rent: return "house"
        case .gifts: return "gift"
        case .other: return "square.grid.2x2"
        }
    }
}

// MARK: - Group calculations

extension ExpenseGroup {
    /// You first, then everyone else alphabetically.
    var sortedMembers: [Person] {
        (members ?? []).sorted {
            if $0.isMe != $1.isMe { return $0.isMe }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var totalSpentMinor: Int {
        (expenses ?? []).reduce(0) { $0 + $1.amountMinor }
    }

    /// Net balance per person id. Positive = is owed money.
    var balances: [UUID: Int] {
        let ledgerExpenses: [LedgerExpense<UUID>] = (expenses ?? []).compactMap { expense in
            guard let payer = expense.paidBy else { return nil }
            var shares: [UUID: Int] = [:]
            for share in expense.shares ?? [] {
                guard let person = share.person else { continue }
                shares[person.id, default: 0] += share.amountMinor
            }
            return LedgerExpense(payer: payer.id, shares: shares)
        }
        let payments: [LedgerPayment<UUID>] = (settlements ?? []).compactMap { s in
            guard let payer = s.payer, let payee = s.payee else { return nil }
            return LedgerPayment(from: payer.id, to: payee.id, amountMinor: s.amountMinor)
        }
        return Ledger.balances(expenses: ledgerExpenses, payments: payments)
    }

    func balance(for person: Person) -> Int {
        balances[person.id] ?? 0
    }

    /// Suggested payments to settle everyone up.
    var suggestedTransfers: [(from: Person, to: Person, amountMinor: Int)] {
        let current = balances
        let ordered = sortedMembers.map { (id: $0.id, amountMinor: current[$0.id] ?? 0) }
        let lookup = Dictionary(sortedMembers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Ledger.simplify(ordered).compactMap { t in
            guard let from = lookup[t.from], let to = lookup[t.to] else { return nil }
            return (from: from, to: to, amountMinor: t.amountMinor)
        }
    }

    /// True when the person paid for, shares in, or settled anything here.
    func hasActivity(for person: Person) -> Bool {
        (expenses ?? []).contains { $0.involves(person) }
            || (settlements ?? []).contains { $0.payer?.id == person.id || $0.payee?.id == person.id }
    }

    /// Plain-text summary for the share sheet (Messages, WhatsApp, email…).
    func shareSummary(me: Person) -> String {
        var lines: [String] = ["\(emoji) \(name)"]
        lines.append("Total spent: \(Money.format(totalSpentMinor, code: currencyCode))")
        lines.append("")
        lines.append("Balances:")
        let current = balances
        for person in sortedMembers {
            let amount = current[person.id] ?? 0
            let name = person.name
            if amount > 0 {
                lines.append("• \(name) gets back \(Money.format(amount, code: currencyCode))")
            } else if amount < 0 {
                lines.append("• \(name) owes \(Money.format(-amount, code: currencyCode))")
            } else {
                lines.append("• \(name) is settled up")
            }
        }
        let transfers = suggestedTransfers
        if !transfers.isEmpty {
            lines.append("")
            lines.append("To settle up:")
            for t in transfers {
                lines.append("• \(t.from.name) pays \(t.to.name) \(Money.format(t.amountMinor, code: currencyCode))")
            }
        }
        lines.append("")
        lines.append("— sent from What's My Share")
        return lines.joined(separator: "\n")
    }
}
