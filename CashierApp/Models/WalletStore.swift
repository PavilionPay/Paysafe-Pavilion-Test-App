import Foundation
import Observation

enum CheckoutOutcome: Equatable {
    case success(reference: String?)
    case cancelled
    /// The Paysafe demo store was dismissed. It has no return path, so the result is unknown to the app.
    case demoClosed
    case failed(String)
}

@MainActor
@Observable
final class WalletStore {
    var balance: Decimal = 0
    var lastOutcome: CheckoutOutcome?
    /// Patron entered in the app; nil uses the server's default TEST patron. Memory only (holds an SSN).
    var patron: Patron?

    private let backend: CashierBackend

    init(backend: CashierBackend = HTTPCashierBackend()) {
        self.backend = backend
    }

    func refreshBalance() async {
        if let value = try? await backend.fetchBalance() {
            balance = value
        }
    }

    func createCashierSession(amount: Decimal) async throws -> String {
        try await backend.createCashierSession(amount: amount, patron: patron)
    }

    /// The redirect back from the cashier page is a hint only. Always confirm the
    /// result with the backend (webhook-driven) before crediting the balance.
    func apply(outcome: CheckoutOutcome) async {
        lastOutcome = outcome
        if case .success = outcome {
            await refreshBalance()
        }
    }
}
