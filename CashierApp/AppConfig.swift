import Foundation

enum AppConfig {
    /// Backend that serves cashier.html and the cashier API (server/server.py).
    /// The simulator reaches the Mac at localhost; on a physical iPhone use the Mac's LAN address,
    /// e.g. http://192.168.1.20:8080. A hosted HTTPS domain enables the Universal Link callback.
    static let cashierBaseURL = URL(string: "http://localhost:8080")!

    /// Page that runs Paysafe Checkout inside the ASWebAuthenticationSession.
    static let cashierPath = "/cashier.html"

    /// Universal Link the cashier page redirects to when finished (HTTPS hosts only).
    static let returnPath = "/cashier-return"

    /// Custom-scheme callback, used for http:// hosts and on iOS < 17.4.
    static let fallbackScheme = "cashierdemo"

    /// Paysafe's public iGaming demo store. Has its own test keys and a VIP Preferred demo customer,
    /// so it runs without a backend, domain or Universal Link. It never redirects back to the app.
    static let paysafeDemoURL = URL(string: "https://checkout.paysafe.com/payments-api/checkout/igaming/index.html")!

    static var cashierURL: URL {
        cashierBaseURL.appending(path: cashierPath)
    }
}
