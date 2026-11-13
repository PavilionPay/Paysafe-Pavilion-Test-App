import SwiftUI

@main
struct CashierApp: App {
    @State private var wallet = WalletStore()

    var body: some Scene {
        WindowGroup {
            LobbyView()
                .environment(wallet)
                .preferredColorScheme(.dark)
                // A /cashier-return link that reaches the app outside the web-auth session is handled like
                // the session callback. Other paths, such as a Plaid OAuth redirect from a bank app
                // (/plaid-oauth), only need to bring the app forward: Plaid Link resumes in the session.
                .onOpenURL { url in
                    guard url.path == AppConfig.returnPath || url.host == "cashier-return" else { return }
                    Task { await wallet.apply(outcome: CheckoutLauncher.parse(url)) }
                }
                .task { await wallet.refreshBalance() }
        }
    }
}
