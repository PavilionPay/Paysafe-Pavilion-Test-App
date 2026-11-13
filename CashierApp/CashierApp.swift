import SwiftUI

@main
struct CashierApp: App {
    @State private var wallet = WalletStore()

    var body: some Scene {
        WindowGroup {
            LobbyView()
                .environment(wallet)
                .preferredColorScheme(.dark)
                // A Universal Link can arrive outside the web-auth session, e.g. when the bank's own app
                // finishes OAuth and hands control back. Treat it the same as the session callback.
                .onOpenURL { url in
                    guard url.path == AppConfig.returnPath || url.host == "cashier-return" else { return }
                    Task { await wallet.apply(outcome: CheckoutLauncher.parse(url)) }
                }
                .task { await wallet.refreshBalance() }
        }
    }
}
