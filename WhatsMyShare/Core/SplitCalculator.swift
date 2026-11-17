import Foundation

// Pure, framework-free money logic. All amounts are integers in the currency's
// minor unit (e.g. cents) so totals always add up exactly.
// This file is compiled into the app AND into the `ShareCore` Swift package
// (see Package.swift) so it can be unit tested with `swift test`.

public enum SplitMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case equal
    case exact
    case percentage
    case shares

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .equal: return "Equally"
        case .exact: return "Exact"
        case .percentage: return "%"
        case .shares: return "Shares"
        }
    }
}

public enum SplitError: Error, Equatable, Sendable {
    case noParticipants
    case invalidTotal
    case negativeValue
    /// Sum of entered exact amounts minus the total (positive = over-assigned).
    case exactMismatch(differenceMinor: Int)
    /// Sum of the entered percentages.
    case percentageMismatch(totalPercent: Double)
    case zeroShares
}

public enum SplitCalculator {

    /// Splits `totalMinor` between `participants`.
    ///
    /// - `values` is ignored for `.equal`.
    /// - `.exact`: values are amounts in minor units.
    /// - `.percentage`: values are percents (must add up to 100).
    /// - `.shares`: values are weights (e.g. 2 shares vs 1 share).
    /// Missing values count as 0. The result always sums to exactly `totalMinor`.
    public static func split<ID: Hashable>(
        totalMinor: Int,
        method: SplitMethod,
        participants: [ID],
        values: [ID: Double] = [:]
    ) throws -> [ID: Int] {
        var seen = Set<ID>()
        let people = participants.filter { seen.insert($0).inserted }

        guard !people.isEmpty else { throw SplitError.noParticipants }
        guard totalMinor > 0 else { throw SplitError.invalidTotal }

        switch method {
        case .equal:
            return allocate(totalMinor: totalMinor, weights: people.map { ($0, 1.0) })

        case .exact:
            var result: [ID: Int] = [:]
            var sum = 0
            for id in people {
                let v = values[id] ?? 0
                guard v >= 0, v.isFinite else { throw SplitError.negativeValue }
                let minor = Int(v.rounded())
                result[id] = minor
                sum += minor
            }
            guard sum == totalMinor else {
                throw SplitError.exactMismatch(differenceMinor: sum - totalMinor)
            }
            return result

        case .percentage:
            var weights: [(ID, Double)] = []
            var sum = 0.0
            for id in people {
                let v = values[id] ?? 0
                guard v >= 0, v.isFinite else { throw SplitError.negativeValue }
                weights.append((id, v))
                sum += v
            }
            guard abs(sum - 100) < 0.001 else {
                throw SplitError.percentageMismatch(totalPercent: sum)
            }
            return allocate(totalMinor: totalMinor, weights: weights)

        case .shares:
            var weights: [(ID, Double)] = []
            var sum = 0.0
            for id in people {
                let v = values[id] ?? 0
                guard v >= 0, v.isFinite else { throw SplitError.negativeValue }
                weights.append((id, v))
                sum += v
            }
            guard sum > 0 else { throw SplitError.zeroShares }
            return allocate(totalMinor: totalMinor, weights: weights)
        }
    }

    /// Proportional allocation using the largest-remainder method, so the
    /// parts always add up to the total and leftover cents go to whoever was
    /// closest to rounding up (ties: earlier participant first).
    static func allocate<ID: Hashable>(totalMinor: Int, weights: [(ID, Double)]) -> [ID: Int] {
        let weightSum = weights.reduce(0.0) { $0 + $1.1 }
        var result: [ID: Int] = [:]
        guard weightSum > 0 else { return result }

        var allocated = 0
        var remainders: [(index: Int, fraction: Double)] = []
        for (index, entry) in weights.enumerated() {
            let exact = Double(totalMinor) * entry.1 / weightSum
            let whole = Int(exact.rounded(.down))
            result[entry.0] = whole
            allocated += whole
            if entry.1 > 0 {
                remainders.append((index, exact - Double(whole)))
            }
        }

        let order = remainders.sorted {
            $0.fraction != $1.fraction ? $0.fraction > $1.fraction : $0.index < $1.index
        }
        var leftover = totalMinor - allocated
        var cursor = 0
        while leftover > 0, !order.isEmpty {
            let id = weights[order[cursor % order.count].index].0
            result[id, default: 0] += 1
            leftover -= 1
            cursor += 1
        }
        return result
    }
}

// MARK: - Balances

public struct LedgerExpense<ID: Hashable> {
    public var payer: ID
    /// What each person owes for this expense. The expense total is the sum.
    public var shares: [ID: Int]

    public init(payer: ID, shares: [ID: Int]) {
        self.payer = payer
        self.shares = shares
    }
}

public struct LedgerPayment<ID: Hashable> {
    /// The person who handed over the money.
    public var from: ID
    /// The person who received it.
    public var to: ID
    public var amountMinor: Int

    public init(from: ID, to: ID, amountMinor: Int) {
        self.from = from
        self.to = to
        self.amountMinor = amountMinor
    }
}

public struct LedgerTransfer<ID: Hashable>: Equatable {
    public var from: ID
    public var to: ID
    public var amountMinor: Int

    public init(from: ID, to: ID, amountMinor: Int) {
        self.from = from
        self.to = to
        self.amountMinor = amountMinor
    }
}

public enum Ledger {

    /// Net balance per person. Positive = others owe them; negative = they owe.
    /// The balances of everyone always sum to zero.
    public static func balances<ID: Hashable>(
        expenses: [LedgerExpense<ID>],
        payments: [LedgerPayment<ID>] = []
    ) -> [ID: Int] {
        var balance: [ID: Int] = [:]
        for expense in expenses {
            let total = expense.shares.values.reduce(0, +)
            balance[expense.payer, default: 0] += total
            for (person, share) in expense.shares {
                balance[person, default: 0] -= share
            }
        }
        for payment in payments {
            balance[payment.from, default: 0] += payment.amountMinor
            balance[payment.to, default: 0] -= payment.amountMinor
        }
        return balance
    }

    /// The fewest-ish payments that settle everyone up (greedy: the biggest
    /// debtor pays the biggest creditor). Input order is used to break ties so
    /// the result is stable.
    public static func simplify<ID: Hashable>(_ balances: [(id: ID, amountMinor: Int)]) -> [LedgerTransfer<ID>] {
        var creditors = balances.filter { $0.amountMinor > 0 }
        var debtors = balances.filter { $0.amountMinor < 0 }.map { (id: $0.id, amountMinor: -$0.amountMinor) }
        var transfers: [LedgerTransfer<ID>] = []

        while let c = creditors.indices.max(by: { creditors[$0].amountMinor < creditors[$1].amountMinor }),
              let d = debtors.indices.max(by: { debtors[$0].amountMinor < debtors[$1].amountMinor }) {
            let amount = min(creditors[c].amountMinor, debtors[d].amountMinor)
            transfers.append(LedgerTransfer(from: debtors[d].id, to: creditors[c].id, amountMinor: amount))
            creditors[c].amountMinor -= amount
            debtors[d].amountMinor -= amount
            if creditors[c].amountMinor == 0 { creditors.remove(at: c) }
            if debtors[d].amountMinor == 0 { debtors.remove(at: d) }
        }
        return transfers
    }
}
