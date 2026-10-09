# Tap App Link Flutter SDK

Attribution SDK for Flutter. Call `configure`, `trackInstall`, and `setAppUserId` with the same billing user id your webhook provider sends.

## Install

```yaml
dependencies:
  tapapplink: ^0.3.2
```

Then `flutter pub get`.

## Usage

```dart
import 'package:flutter/foundation.dart';
import 'package:tapapplink/tapapplink.dart';

TapAppLink.configure(TapAppLinkConfig(
  publicKey: 'etk_live_…',
  environment: kDebugMode
      ? TapAppLinkEnvironment.sandbox
      : TapAppLinkEnvironment.production,
  debug: kDebugMode,
));

await TapAppLink.trackInstall();
await TapAppLink.setAppUserId(await Purchases.appUserID);

final offer = TapAppLink.getOffer();
```

`trackInstall()` is safe on every launch. It creates a stable `installId` once, posts `/ingestInstall` only on the first open, and restores the attribution id and offer from local storage on later launches. On Android it reads the Play Install Referrer unless you pass `installReferrer:` yourself. iOS and other platforms skip the native referrer.

Set `debug: true` on `TapAppLinkConfig` to log each request, response and stored state. The API key is redacted in those logs.

Call `resetForTesting()` in debug builds before repeating a match test on the same install.

Purchases are attributed through billing webhooks. Leave out a client `trackPurchase` call.

## Applying a code

`applyCode` returns success JSON only on a real 2xx result. Map each outcome to UI state like this:

```dart
String title;
String? subtitle;
String? shownCode;
String? offerLine;

try {
  final result = await TapAppLink.applyCode(code);
  final offerJson = result['offer'];
  if (offerJson is Map) {
    final name = offerJson['creatorName'];
    final promo = offerJson['promoCode'];
    if (name is String && name.isNotEmpty) {
      offerLine = promo is String && promo.isNotEmpty
          ? '$name · $promo'
          : name;
    }
  }

  if (result['alreadyAttributed'] == true) {
    // Success with alreadyAttributed true
    title = "You're all set";
    shownCode = null; // hide the code
    subtitle = offerLine;
  } else {
    // Success with a new attribution
    title = 'Code applied';
    shownCode = code;
    subtitle = offerLine;
  }
} on TapAppLinkUnknownCodeException {
  title = "We don't recognise that code. Check it and try again.";
  subtitle = "Codes aren't case sensitive.";
} on TapAppLinkWrongEnvironmentException {
  // Same customer copy as unknownCode. Never show the word "environment".
  title = "We don't recognise that code. Check it and try again.";
  subtitle = "Codes aren't case sensitive.";
  debugPrint(TapAppLinkWrongEnvironmentException.developerWarning);
  // "This code belongs to the other environment (Sandbox or Production). Check your API key."
} on TapAppLinkInactiveCodeException {
  title = 'This code is no longer active.';
  subtitle = 'You can still subscribe at the regular price.';
} on TapAppLinkNetworkException {
  title = "We couldn't check your code. Check your connection and try again.";
} on TapAppLinkApplyCodeOtherException catch (error) {
  title = "We couldn't check your code. Check your connection and try again.";
  debugPrint('applyCode failed status=${error.status} message=${error.message}');
}
```

Typed failures from `applyCode`:

| Exception | Case |
| --- | --- |
| `TapAppLinkUnknownCodeException` | `unknownCode` |
| `TapAppLinkInactiveCodeException` | `inactiveCode` |
| `TapAppLinkWrongEnvironmentException` | `wrongEnvironment` |
| `TapAppLinkNetworkException` | network / timeout |
| `TapAppLinkApplyCodeOtherException` | `other` (has `status` and `message`) |

## Publishing

CI runs format, analyse, test, publish dry-run, and an example Android debug build on every PR and push to `main`.

Releases publish to [pub.dev](https://pub.dev/packages/tapapplink) from GitHub Actions via OIDC (no stored token). Push a tag that matches the package version, for example:

```bash
git tag v0.3.2
git push origin v0.3.2
```

The `version` in `pubspec.yaml` must match the tag (here `0.3.2`).

### One-time pub.dev admin setting (Kenny)

On https://pub.dev/packages/tapapplink/admin, under **Automated publishing**:

1. Enable publishing from GitHub Actions.
2. Repository: `tapapplink/tapapplink-flutter`
3. Tag pattern: `v{{version}}`

Without that, tag pushes will not be allowed to publish.

## License

MIT
