#if DEBUG
import Foundation

/// `-seed` on the launch arguments: a fixed set of Wallet-shaped accounts and rows pushed through the real
/// `financekit-sync` path, so screens can be checked on the simulator (no Wallet there, and no sandbox bank any more).
enum DebugSeed {
    static let wallet = """
    {"accounts": [
      {"id": "DEB00000-0000-0000-0000-000000000001", "name": "Apple Card", "institution": "Apple Card", "currency": "USD", "kind": "liability", "creditLimit": 12000},
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
    """
}
#endif
