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

The Plaid OAuth redirect URI is a different URL from the cashier return URL above:

| | Cashier return URL | Plaid OAuth redirect URI |
|---|---|---|
| Purpose | Ends the cashier session and hands the result to the app | Brings the patron back to Plaid Link after the bank's OAuth login, mid-flow |
| Who sets it | You (`cashier.html`, `AppConfig.returnPath`) | Paysafe Checkout, on the link token Pavilion creates |
| Default value | `https://<your-host>/cashier-return` or `cashierdemo://cashier-return` | Paysafe's hosted VIP Preferred page, e.g. `https://hosted.paysafe.com/vippreferred/v1/index.html` (TEST: `hosted.test.paysafe.com`) |
| Registered with Plaid? | No | Yes, as an allowed redirect URI on Pavilion's Plaid client |

### How the redirect URI reaches Plaid

1. When the patron chooses to link a bank, Paysafe Checkout asks Pavilion VIP Preferred for a Plaid link token and
   includes the redirect URI in that request.
2. Pavilion creates the link token with Plaid using that `redirect_uri`. Plaid accepts it only if it's on the
   client's allowed list, which Pavilion maintains.
3. Checkout opens Plaid Link with the token. After the bank login, the bank sends the patron to the redirect URI and
   Link resumes.

Your app and backend never call Plaid directly and never see the link token.

### Bank login in the browser (works with the sample as is)

If the patron doesn't have the bank's app, the bank's OAuth page opens inside the same `ASWebAuthenticationSession`.
The bank redirects to Paysafe's hosted page, still in that Safari session, and Link resumes there. Nothing needs to be
registered by you. This was verified with Plaid's sandbox OAuth bank.

### App-to-app OAuth (the bank's app opens)

If the bank's app is installed, iOS may open it instead of the web login. When the patron finishes, the bank app
opens the redirect URI. With the default (Paysafe's web page), that lands in Safari, not in your app. To return to
your app, the redirect URI has to be a **Universal Link your app claims**.

> **Confirm with Paysafe.** The fields below come from Paysafe's integration team and are not yet in Paysafe's public
> Checkout docs. Confirm the names and behavior with Paysafe before you rely on them.

Paysafe Checkout accepts the merchant's Universal Link in the VIP Preferred options and forwards it to Pavilion:

```js
paymentMethodDetails: {
  vippreferred: {
    consumerId: '<9-digit SSN>',
    deepLink: 'https://cashier.example.com/plaid-oauth',   // your Universal Link (confirm with Paysafe)
    isMobile: true,                                         // patron is in a native app (confirm with Paysafe)
  },
},
```

To make that work:

1. **Choose a dedicated path**, such as `/plaid-oauth`. Don't reuse `/cashier-return`: this link arrives mid-flow
   and isn't a payment result.
2. **Claim it in your AASA file** by adding it to `components` next to the return path:
   ```json
   { "/": "/plaid-oauth*", "comment": "Plaid OAuth redirect from bank apps" }
   ```
3. **Have Pavilion register the exact URL** as an allowed redirect URI on the Plaid client used by VIP Preferred.
   It must match character for character, including any trailing slash.
4. **Let the app simply come to the front.** Plaid Link resumes inside the cashier session; the app doesn't need to
   parse or forward the URL. The sample's `onOpenURL` handler only acts on `/cashier-return` and ignores other paths.

The sample doesn't send `deepLink` or `isMobile` yet. Add them in `web/cashier.html` once your Universal Link is
registered.

## Testing the return

1. Run the app with an HTTPS `cashierBaseURL` on iOS 17.4+.
2. Start a deposit and finish or cancel Checkout.
3. The session should close by itself and the cashier should show the outcome. If Safari instead loads
   `https://<host>/cashier-return` and shows "Payment finished. Return to the app.", iOS didn't match the Universal
   Link. Recheck the entitlement, the AASA file and the CDN copy.
