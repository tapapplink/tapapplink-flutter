# Tap App Link Flutter SDK

Attribution SDK for Flutter. Call `configure`, `trackInstall`, and `setAppUserId` with the same billing user id your webhook provider sends.

## Install

```yaml
dependencies:
  tapapplink: ^0.1.0
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
));

await TapAppLink.trackInstall();
await TapAppLink.setAppUserId(await Purchases.appUserID);

final offer = TapAppLink.getOffer();
await TapAppLink.applyCode('SARAH10');
```

`trackInstall()` is safe on every launch — it only records once per install. Call `resetForTesting()` in debug builds before repeating a match test on the same install.

Purchases are attributed through billing webhooks. Leave out a client `trackPurchase` call.

## License

MIT
