import XCTest
@testable import ShareCore

final class SplitCalculatorTests: XCTestCase {

    func testEqualSplitDistributesLeftoverCents() throws {
        let result = try SplitCalculator.split(totalMinor: 1000, method: .equal, participants: ["a", "b", "c"])
        XCTAssertEqual(result, ["a": 334, "b": 333, "c": 333])
        XCTAssertEqual(result.values.reduce(0, +), 1000)
    }

    func testEqualSplitIgnoresDuplicates() throws {
        let result = try SplitCalculator.split(totalMinor: 100, method: .equal, participants: ["a", "a", "b"])
        XCTAssertEqual(result, ["a": 50, "b": 50])
    }

    func testExactSplitMustAddUp() throws {
        let ok = try SplitCalculator.split(totalMinor: 1000, method: .exact, participants: ["a", "b"],
                                           values: ["a": 700, "b": 300])
        XCTAssertEqual(ok, ["a": 700, "b": 300])

        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 1000, method: .exact, participants: ["a", "b"],
                                                       values: ["a": 700, "b": 200])) { error in
            XCTAssertEqual(error as? SplitError, .exactMismatch(differenceMinor: -100))
        }
    }

    func testPercentageSplit() throws {
        let result = try SplitCalculator.split(totalMinor: 999, method: .percentage, participants: ["a", "b", "c"],
                                               values: ["a": 50, "b": 25, "c": 25])
        XCTAssertEqual(result.values.reduce(0, +), 999)
        XCTAssertEqual(result["a"], 500)

        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 999, method: .percentage, participants: ["a", "b"],
                                                       values: ["a": 50, "b": 40]))
    }

    func testSharesSplit() throws {
        let result = try SplitCalculator.split(totalMinor: 900, method: .shares, participants: ["a", "b"],
                                               values: ["a": 2, "b": 1])
        XCTAssertEqual(result, ["a": 600, "b": 300])

        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 900, method: .shares, participants: ["a"],
                                                       values: ["a": 0])) { error in
            XCTAssertEqual(error as? SplitError, .zeroShares)
        }
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 100, method: .equal, participants: [String]()))
        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 0, method: .equal, participants: ["a"]))
        XCTAssertThrowsError(try SplitCalculator.split(totalMinor: 100, method: .shares, participants: ["a"],
                                                       values: ["a": -1]))
    }

    func testBalancesAndSettlements() {
        // Alice paid 90 for dinner split three ways; Bob paid 30 for taxi split with Carol.
        let expenses = [
            LedgerExpense(payer: "alice", shares: ["alice": 30, "bob": 30, "carol": 30]),
            LedgerExpense(payer: "bob", shares: ["bob": 15, "carol": 15])
        ]
        var balances = Ledger.balances(expenses: expenses)
        XCTAssertEqual(balances, ["alice": 60, "bob": -15, "carol": -45])
        XCTAssertEqual(balances.values.reduce(0, +), 0)

        // Carol pays Alice 45.
        balances = Ledger.balances(expenses: expenses,
                                   payments: [LedgerPayment(from: "carol", to: "alice", amountMinor: 45)])
        XCTAssertEqual(balances, ["alice": 15, "bob": -15, "carol": 0])
    }

    func testSimplify() {
        let transfers = Ledger.simplify([
            (id: "alice", amountMinor: 60),
            (id: "bob", amountMinor: -15),
            (id: "carol", amountMinor: -45)
        ])
        XCTAssertEqual(transfers, [
            LedgerTransfer(from: "carol", to: "alice", amountMinor: 45),
            LedgerTransfer(from: "bob", to: "alice", amountMinor: 15)
        ])
    }

    func testSimplifyAlreadySettled() {
        XCTAssertTrue(Ledger.simplify([(id: "a", amountMinor: 0), (id: "b", amountMinor: 0)]).isEmpty)
    }
}
