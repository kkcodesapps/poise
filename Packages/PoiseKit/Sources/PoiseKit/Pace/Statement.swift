import Foundation

/// Wallet shares a card's due date and minimum but not the statement balance, so for Apple Card the statement is rebuilt
/// from the rows: the cycle is the calendar month before the due date's month (Apple Card closes on the last day of a
/// month and is due at the end of the next); what's owed on it is everything that posted inside that month except
/// payments, less anything paid since the close. Exact for a card paid in full — a balance carried from earlier isn't
/// visible here.
public enum StatementEstimator {
    public static func statement(for account: Account, transactions: [Transaction], calendar: Calendar = .current) -> Decimal? {
        guard account.role == .credit, let due = account.statementDue,
              let dueMonth = calendar.dateInterval(of: .month, for: due),
              let cycle = calendar.dateInterval(of: .month, for: dueMonth.start.addingTimeInterval(-1)) else { return nil }
        let rows = transactions.filter { $0.accountID == account.id && !$0.pending }
        let isPayment: (Transaction) -> Bool = { ($0.kind == .ccPayment || $0.kind == .transfer) && $0.amount > 0 }
        let owed = rows.filter { cycle.holds($0.date) && !isPayment($0) }.reduce(Decimal(0)) { $0 - $1.amount }   // charges add, refunds subtract
        let paidSince = rows.filter { $0.date >= cycle.end && isPayment($0) }.reduce(Decimal(0)) { $0 + $1.amount }
        guard !rows.contains(where: { cycle.holds($0.date) }) else { return max(0, (owed - paidSince).roundedToCents) }
        return nil   // nothing from that month on the phone: no guess
    }
}
