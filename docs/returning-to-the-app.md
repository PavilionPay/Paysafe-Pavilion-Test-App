# Returning to the app

When the patron finishes in Paysafe Checkout, the cashier has to close and hand the result back to your app. You
control this with **one URL, the return URL**. Nothing else needs to be registered or handled by your app.

## Terms

| Term | What it means here |
|---|---|
| **Return URL** | The URL the cashier page navigates to when Checkout finishes. Reaching it closes the cashier and gives your app the result. **You set it.** |
| **Custom scheme** | One way to build the return URL: `yourapp://cashier-return?...`. Works everywhere, with no server setup. |
| **Universal Link** | The other way: an `https://` return URL on your own domain, such as `https://cashier.example.com/cashier-return?...`. Apple verifies that the domain belongs to your app, so no other app can receive it. |
| **Bank OAuth redirect URL** | Where the bank sends the patron after they log in to link a bank account. It belongs to Paysafe and Pavilion, and Plaid uses it. **You don't set it or handle it.** |

A Universal Link is not a separate URL. It's a property of an `https://` URL, so it's an option for the return URL,
not another URL to manage.

## What you need to do

1. **Open the cashier in `ASWebAuthenticationSession`**, not an embedded `WKWebView`
   ([why](#why-aswebauthenticationsession)).
2. **Pick how the return URL reaches the app:** a custom scheme or a Universal Link
   ([which one](#custom-scheme-or-universal-link)).
3. **Navigate to the return URL when Checkout finishes**, with the outcome in the query string.
4. **Treat the outcome as a hint.** Ask your backend for the payment's real status before you update the balance.

In this sample:

| Step | Where |
|---|---|
| 1, 2 | `CheckoutLauncher.swift` starts the session and chooses the callback (Universal Link on HTTPS and iOS 17.4+, otherwise the `cashierdemo` scheme). |
| 3 | `finish()` in `web/cashier.html` calls `location.replace()` with `/cashier-return?status=...&ref=...`. |
| 4 | `WalletStore.apply(outcome:)` refreshes the balance from the backend. |

## Why `ASWebAuthenticationSession`

When a patron links a bank with Online Banking, Plaid sends them to the bank's own login page and then back to the
bank OAuth redirect URL, where linking continues. `ASWebAuthenticationSession` runs on Safari, so all of that happens
inside one session with no setup on your side. Embedded `WKWebView`s are not reliably supported for bank OAuth: some
banks block their login pages there, and the patron may not get back to Checkout.

The session also ends by itself when the page reaches your return URL, which is what hands the result to the app.

## Custom scheme or Universal Link

| | Custom scheme | Universal Link |
|---|---|---|
| Return URL | `cashierdemo://cashier-return?...` | `https://<your-host>/cashier-return?...` |
| Requirements | Any iOS version, any cashier host (including `http://` for local testing) | iOS 17.4+ and an HTTPS cashier host on your domain |
| Setup | `CFBundleURLTypes` in `project.yml` (already done in the sample) | Associated Domains, entitlement and AASA file ([below](#setting-up-the-universal-link-return)) |
| Can another app receive it? | Yes, any app can claim the same scheme | No, Apple verifies the domain |
| Recommendation | Development and testing | Production |

Use your own scheme name, not `cashierdemo`.

## Setting up the Universal Link return

### 1. Host the cashier on HTTPS

Serve `web/` and the cashier API from one HTTPS origin you control, for example `https://cashier.example.com`.
The Universal Link host must be the same host the cashier page runs on, because the page navigates to
`${location.origin}/cashier-return`.

### 2. Enable Associated Domains for the app ID

In the Apple Developer portal, open the app's identifier (the sample uses `com.pavilionpay.cashierdemo`) and enable
the **Associated Domains** capability. Set your team ID in `project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "ABCDE12345"
```

### 3. Add the entitlement

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

### 4. Publish the apple-app-site-association file

Serve `web/.well-known/apple-app-site-association` at `https://cashier.example.com/.well-known/apple-app-site-association`,
with `TEAMID` replaced by your team ID:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.pavilionpay.cashierdemo"],
        "components": [
          { "/": "/cashier-return*", "comment": "Cashier return" }
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

### 5. Point the app at the host

In `CashierApp/AppConfig.swift`:

```swift
static let cashierBaseURL = URL(string: "https://cashier.example.com")!
```

`AppConfig.returnPath` (`/cashier-return`) must match the AASA `components` path. Rebuild and reinstall; iOS fetches
the AASA file when the app is installed.

### 6. Test it

1. Run the app with the HTTPS `cashierBaseURL` on iOS 17.4+.
2. Start a deposit and finish or cancel Checkout.
3. The session should close by itself and the app should show the outcome. If Safari instead loads
   `https://<host>/cashier-return` and shows "Payment finished. Return to the app.", iOS didn't match the Universal
   Link. Recheck the entitlement, the AASA file and the CDN copy.

## Bank login: nothing to configure

The bank OAuth redirect URL is Paysafe's hosted page. Paysafe and Pavilion set it up with Plaid, and the patron
returns to it inside the same `ASWebAuthenticationSession`. You don't register anything with Plaid, and your app
doesn't need to handle any bank or Plaid link. Your app only ever receives the return URL.
