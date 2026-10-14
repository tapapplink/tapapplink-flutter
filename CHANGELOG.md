# Changelog

## 0.3.3

- **Fixed:** `setAppUserId` posted `/ingestIdentify` on every call, so apps that link the billing user id from several places (for example Keep Maps) could fire it three times per launch. 0.3.3 skips when the id matches the last successfully identified value (persisted like `trackInstall`), and coalesces concurrent identical calls into one request. A different id still posts.
- Add optional `codeMatches` and `offer.creatorName` on the typed `TapAppLinkRedeemResult` from `applyCode` (matches server redeem response fields).
- Send `X-TapAppLink-SDK-Version: 0.3.3` on all requests.

## 0.3.2

- **Fixed:** retrying `applyCode` after a timeout could count an install twice. 0.3.2 sends a request ID so the server recognises the retry. No code changes needed.

## 0.3.1

- **Fixed:** Android and React Native 0.3.0 could return an error from `applyCode()` as if it were a normal result, so an app could show a code as applied when it wasn't. Upgrade to 0.3.1, which raises a typed error for unknown, inactive and wrong-environment codes. iOS and Flutter 0.3.0 threw a generic error, and 0.3.1 makes it typed.
- Check HTTP status on every SDK request; non-2xx responses are never treated as success.
- Send `X-TapAppLink-SDK-Version: 0.3.1` on all requests.

## 0.3.0

- Persist install state with `shared_preferences` (install id, tracked flag, attribution id, offer).
- Send a stable `installId` on `/ingestInstall` so the server can dedupe.
- Turn the package into a Flutter plugin with an Android Play Install Referrer reader; iOS and other platforms are a no-op.
- Honour an optional `installReferrer` override and time out when the referrer API is unavailable.
- Add opt-in `debug` logging on `TapAppLinkConfig` (requests, responses, stored state; API key redacted).
- Extend CI to build the example Android app so the plugin side is compiled.

## 0.2.0

- Remove `discountBps` from `TapAppLinkOffer`. Present `billingOfferId` on the paywall.

## 0.1.2

- Remove unused `debugSessionId` from `configure()`. The sandbox debugger attaches via the QR link or code watch.

## 0.1.1

- Point repository and issue tracker at the tapapplink GitHub org.

## 0.1.0

- First public Flutter release.
- `TapAppLink` API aligned with the other platform SDKs.
