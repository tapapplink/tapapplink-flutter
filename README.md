# Tap App Link Flutter SDK

Attribution SDK for Flutter. Call `configure`, `trackInstall`, and `setAppUserId` with the same billing user id your webhook provider sends.

## Install

```yaml
dependencies:
  tapapplink: ^0.3.0
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
await TapAppLink.applyCode('SARAH10');
```

`trackInstall()` is safe on every launch. It creates a stable `installId` once, posts `/ingestInstall` only on the first open, and restores the attribution id and offer from local storage on later launches. On Android it reads the Play Install Referrer unless you pass `installReferrer:` yourself. iOS and other platforms skip the native referrer.

Set `debug: true` on `TapAppLinkConfig` to log each request, response and stored state. The API key is redacted in those logs.

Call `resetForTesting()` in debug builds before repeating a match test on the same install.

Purchases are attributed through billing webhooks. Leave out a client `trackPurchase` call.

## Publishing

CI runs format, analyse, test, publish dry-run, and an example Android debug build on every PR and push to `main`.

Releases publish to [pub.dev](https://pub.dev/packages/tapapplink) from GitHub Actions via OIDC (no stored token). Push a tag that matches the package version, for example:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The `version` in `pubspec.yaml` must match the tag (here `0.3.0`).

### One-time pub.dev admin setting (Kenny)

On https://pub.dev/packages/tapapplink/admin, under **Automated publishing**:

1. Enable publishing from GitHub Actions.
2. Repository: `tapapplink/tapapplink-flutter`
3. Tag pattern: `v{{version}}`

Without that, tag pushes will not be allowed to publish.

## License

MIT
