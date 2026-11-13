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
                // the session callback. Other links (for example a Plaid redirect) are ignored here;
                // see docs/universal-links.md §6.
                .onOpenURL { url in
                    guard url.path == AppConfig.returnPath || url.host == "cashier-return" else { return }
                    Task { await wallet.apply(outcome: CheckoutLauncher.parse(url)) }
                }
                .task { await wallet.refreshBalance() }
        }
    }
}
