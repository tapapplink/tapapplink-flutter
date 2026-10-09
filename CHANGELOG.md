# Changelog

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
