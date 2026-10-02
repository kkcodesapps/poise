#if DEBUG
import Foundation
import PoiseKit

/// `-seed` on the launch arguments: a fixed set of Wallet-shaped accounts and rows pushed through the real
/// `financekit-sync` path, so screens can be checked on the simulator (no Wallet there, and no sandbox bank any more).
enum DebugSeed {
    /// The Apple Card's statement lands eight days out, so Next 14 and the account page have something to show.
    static var wallet: String { """
    {"accounts": [
      {"id": "DEB00000-0000-0000-0000-000000000001", "name": "Apple Card", "institution": "Apple Card", "currency": "USD", "kind": "liability", "creditLimit": 12000, "nextPaymentDue": "\(WalletSource.Payload.day(Calendar.current.date(byAdding: .day, value: 8, to: .now) ?? .now))", "minimumPayment": 25},
      {"id": "DEB00000-0000-0000-0000-000000000002", "name": "Apple Cash", "institution": "Apple Cash", "currency": "USD", "kind": "asset"},
      {"id": "DEB00000-0000-0000-0000-000000000003", "name": "Savings", "description": "Apple Card Savings", "institution": "Goldman Sachs", "currency": "USD", "kind": "asset"}],
     "balances": [
      {"accountID": "DEB00000-0000-0000-0000-000000000001", "booked": {"amount": 1284.16, "debit": false}, "asOf": "2026-09-17T12:00:00Z"},
      {"accountID": "DEB00000-0000-0000-0000-000000000002", "booked": {"amount": 96.40, "debit": true}, "asOf": "2026-09-17T12:00:00Z"},
      {"accountID": "DEB00000-0000-0000-0000-000000000003", "booked": {"amount": 4210.55, "debit": true}, "asOf": "2026-09-17T12:00:00Z"}],
     "transactions": [
      {"id": "seed-1", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 76.79, "currency": "USD", "debit": true, "description": "Instacart", "merchant": "Instacart", "mcc": 5411, "type": "pointOfSale", "status": "booked", "date": "2026-09-16", "postedDate": "2026-09-16"},
      {"id": "seed-2", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 26.99, "currency": "USD", "debit": true, "description": "Netflix", "merchant": "Netflix", "mcc": 4899, "type": "pointOfSale", "status": "booked", "date": "2026-09-15", "postedDate": "2026-09-15"},
      {"id": "seed-3", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 14.20, "currency": "USD", "debit": true, "description": "Chipotle", "merchant": "Chipotle", "mcc": 5814, "type": "pointOfSale", "status": "pending", "date": "2026-09-17", "postedDate": null},
      {"id": "seed-4", "accountID": "DEB00000-0000-0000-0000-000000000002", "amount": 1.54, "currency": "USD", "debit": false, "description": "Deposit", "merchant": null, "mcc": null, "type": "deposit", "status": "booked", "date": "2026-09-16", "postedDate": "2026-09-16"},
      {"id": "seed-5", "accountID": "DEB00000-0000-0000-0000-000000000003", "amount": 17.42, "currency": "USD", "debit": false, "description": "Interest", "merchant": null, "mcc": null, "type": "interest", "status": "booked", "date": "2026-09-01", "postedDate": "2026-09-01"},
      {"id": "seed-6", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 24.99, "currency": "USD", "debit": true, "description": "Netflix", "merchant": "Netflix", "mcc": 4899, "type": "pointOfSale", "status": "booked", "date": "2026-08-15", "postedDate": "2026-08-15"},
      {"id": "seed-7", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 24.99, "currency": "USD", "debit": true, "description": "Netflix", "merchant": "Netflix", "mcc": 4899, "type": "pointOfSale", "status": "booked", "date": "2026-07-15", "postedDate": "2026-07-15"},
      {"id": "seed-8", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 14.20, "currency": "USD", "debit": true, "description": "Chipotle", "merchant": "Chipotle", "mcc": 5814, "type": "pointOfSale", "status": "pending", "date": "2026-09-16", "postedDate": null},
      {"id": "seed-9", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 3.10, "currency": "USD", "debit": true, "description": "Interest charge", "merchant": null, "mcc": null, "type": "interest", "status": "booked", "date": "2026-09-15", "postedDate": "2026-09-15"}]}
    """ }

    /// `-seed-payroll`: three biweekly Friday deposits into Savings, so an income stream (and the payday screens) exists.
    static var payroll: String {
        let cal = Calendar.current
        let friday = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now)) }.first { cal.component(.weekday, from: $0) == 6 }!
        let rows = (0..<3).map { i -> String in
            let d = WalletSource.Payload.day(cal.date(byAdding: .day, value: -14 * i, to: friday)!)
            return """
            {"id": "seed-pay-\(i)", "accountID": "DEB00000-0000-0000-0000-000000000003", "amount": 2150.00, "currency": "USD", "debit": false, "description": "ACME PAYROLL", "merchant": "Acme Payroll", "mcc": null, "type": "deposit", "status": "booked", "date": "\(d)", "postedDate": "\(d)"}
            """
        }
        return "{\"transactions\": [\(rows.joined(separator: ","))]}"
    }

    /// `-seed-bills`: three months of rent + parking on the 2nd (Apple Cash), a car payment on the 11th, semi-monthly pay on the
    /// 15th and the last day, and Spotify on the Apple Card at month end — the shapes Next 14 has to get right.
    static var bills: String {
        let cal = Calendar.current
        let cash = "DEB00000-0000-0000-0000-000000000002", card = "DEB00000-0000-0000-0000-000000000001"
        func row(_ id: String, _ acct: String, _ amount: Double, debit: Bool, _ desc: String, _ merchant: String, mcc: Int?, type: String, _ d: Date) -> String {
            let day = WalletSource.Payload.day(d)
            return "{\"id\": \"\(id)\", \"accountID\": \"\(acct)\", \"amount\": \(amount), \"currency\": \"USD\", \"debit\": \(debit), \"description\": \"\(desc)\", \"merchant\": \"\(merchant)\", \"mcc\": \(mcc.map(String.init) ?? "null"), \"type\": \"\(type)\", \"status\": \"booked\", \"date\": \"\(day)\", \"postedDate\": \"\(day)\"}"
        }
        var rows: [String] = []
        for back in 1...3 {
            let month = cal.date(byAdding: .month, value: -back, to: .now)!
            let second = Cadence.dayOfMonth(2, in: month, calendar: cal), eleventh = Cadence.dayOfMonth(11, in: month, calendar: cal)
            let fifteenth = Cadence.beforeWeekend(Cadence.dayOfMonth(15, in: month, calendar: cal), calendar: cal), last = Cadence.beforeWeekend(Cadence.endOfMonth(of: month, calendar: cal), calendar: cal)
            rows.append(row("seed-rent-\(back)", cash, 4110, debit: true, "MODA HOMES", "Moda Homes", mcc: 6513, type: "billPayment", second))
            rows.append(row("seed-park-\(back)", cash, 200, debit: true, "MODA HOMES", "Moda Homes", mcc: 6513, type: "billPayment", second))
            rows.append(row("seed-car-\(back)", cash, 799.45, debit: true, "TD AUTO FINANCE", "TD Auto Finance", mcc: nil, type: "directDebit", eleventh))
            rows.append(row("seed-pay-a-\(back)", cash, 4557.32, debit: false, "SQUIZ PAYROLL", "Squiz Payroll", mcc: nil, type: "directDeposit", fifteenth))
            rows.append(row("seed-pay-b-\(back)", cash, 4557.32, debit: false, "SQUIZ PAYROLL", "Squiz Payroll", mcc: nil, type: "directDeposit", last))
            rows.append(row("seed-spot-\(back)", card, 12.99, debit: true, "SPOTIFY", "Spotify", mcc: 4899, type: "pointOfSale", last))
        }
        return "{\"transactions\": [\(rows.joined(separator: ","))]}"
    }

    static let more = """
    {"transactions": [
      {"id": "seed-more-\(Int(Date.now.timeIntervalSince1970))", "accountID": "DEB00000-0000-0000-0000-000000000001", "amount": 48.10, "currency": "USD", "debit": true, "description": "Shell", "merchant": "Shell", "mcc": 5541, "type": "pointOfSale", "status": "booked", "date": "\(WalletSource.Payload.day(.now))", "postedDate": "\(WalletSource.Payload.day(.now))"}]}
    """
}
#endif
