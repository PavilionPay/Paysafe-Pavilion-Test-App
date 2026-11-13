# Registering the Universal Link

The cashier session has to hand control back to the app when Checkout finishes. This sample supports two ways:

| | Custom scheme | Universal Link |
|---|---|---|
| Return URL | `cashierdemo://cashier-return?...` | `https://<your-host>/cashier-return?...` |
| When it's used | `http://` hosts (local testing) and iOS < 17.4 | HTTPS host and iOS 17.4+ |
| Setup | `CFBundleURLTypes` in `project.yml` (already done) | Domain, AASA file and entitlement (below) |
| Can another app claim it? | Yes | No: Apple verifies the domain |

`CheckoutLauncher.swift` picks automatically. When `AppConfig.cashierBaseURL` is HTTPS and the device runs iOS 17.4+,
it starts `ASWebAuthenticationSession` with `callback: .https(host:path:)`; otherwise it uses the custom scheme.
`cashier.html` gets told which one to use (`cb=https` or `cb=scheme`) and redirects to the matching URL.

## 1. Host the cashier on HTTPS

Serve `web/` and the cashier API from one HTTPS origin you control, for example `https://cashier.example.com`.
The Universal Link host must be the same host the cashier page runs on, because the page redirects to
`${location.origin}/cashier-return`.

## 2. Enable Associated Domains for the app ID

In the Apple Developer portal, open the app's identifier (the sample uses `com.pavilionpay.cashierdemo`) and enable
the **Associated Domains** capability. Set your team ID in `project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "ABCDE12345"
```

## 3. Add the entitlement

Edit `CashierApp/CashierApp.entitlements` and replace the placeholder host:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:cashier.example.com</string>
  <string>webcredentials:cashier.example.com</string>
</array>
```

While iterating on a test device you can add `?mode=developer` (`applinks:cashier.example.com?mode=developer`) and
turn on **Settings → Developer → Associated Domains Development**. iOS then fetches the AASA file from your server
directly instead of Apple's CDN, so changes show up right away.

## 4. Publish the apple-app-site-association file

Serve `web/.well-known/apple-app-site-association` at `https://cashier.example.com/.well-known/apple-app-site-association`,
with `TEAMID` replaced by your team ID:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.pavilionpay.cashierdemo"],
        "components": [
          { "/": "/cashier-return*", "comment": "Plaid OAuth / cashier completion return" }
        ]
      }
    ]
  },
  "webcredentials": { "apps": ["ABCDE12345.com.pavilionpay.cashierdemo"] }
}
```

Requirements that commonly break it:

- **Every app ID needs the team ID prefix** (`ABCDE12345.` in front of the bundle ID). Without it iOS ignores the entry.
- **HTTPS with a valid certificate, HTTP 200, no redirects.**
- **`Content-Type: application/json`.** Some static hosts serve the extensionless file as
  `application/octet-stream`. If yours does, publish a copy named `apple-app-site-association.json` and add a rewrite
  from the extensionless path to it, so the type comes from the `.json` extension.
- **Merge, don't replace.** If the domain already serves an AASA file for other apps, add your entry to it.
  Replacing the file breaks the other apps' links.

Check it:

```sh
# What your server returns
curl -sI https://cashier.example.com/.well-known/apple-app-site-association
# What Apple's CDN has cached (devices read this copy; it can lag your server by a while)
curl -s https://app-site-association.cdn-apple.com/a/v1/cashier.example.com
```

## 5. Point the app at the host

In `CashierApp/AppConfig.swift`:

```swift
static let cashierBaseURL = URL(string: "https://cashier.example.com")!
```

`AppConfig.returnPath` (`/cashier-return`) must match the AASA `components` path. Rebuild and reinstall; iOS fetches
the AASA file when the app is installed.

## 6. Plaid OAuth redirect

With Online Banking, Plaid sends the patron to their bank's OAuth page and then back to a **redirect URI** registered
for the Plaid client. Two cases:

- **Bank login in the browser** (the patron doesn't have the bank's app). Everything stays inside the
  `ASWebAuthenticationSession`, and the redirect returns to Checkout in the same Safari session. This works with the
  sample as is; it was verified with Plaid's sandbox OAuth bank.
- **App-to-app OAuth** (the bank's app is installed and opens instead). The bank app returns by opening the redirect
  URI. To land back in your app, that URI must be a Universal Link your app claims, and it must be registered as an
  allowed redirect URI for the Plaid client used by VIP Preferred. Pavilion manages that Plaid client, and Paysafe
  Checkout passes the redirect URI when it starts Link, so coordinate the URI with both before relying on app-to-app
  OAuth. Add the path to your AASA `components` as well.

## Testing the return

1. Run the app with an HTTPS `cashierBaseURL` on iOS 17.4+.
2. Start a deposit and finish or cancel Checkout.
3. The session should close by itself and the cashier should show the outcome. If Safari instead loads
   `https://<host>/cashier-return` and shows "Payment finished. Return to the app.", iOS didn't match the Universal
   Link. Recheck the entitlement, the AASA file and the CDN copy.
