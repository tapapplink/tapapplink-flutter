# Tap App Link Flutter SDK

Attribution SDK for Flutter. Call `configure`, `trackInstall`, and `setAppUserId` with the same billing user id your webhook provider sends.

## Install

```yaml
dependencies:
  tapapplink: ^0.1.0
```

Until pub.dev is live, path-depend on this repo.

## Usage

```dart
import 'package:tapapplink/tapapplink.dart';

TapAppLink.configure(TapAppLinkConfig(
  publicKey: 'etk_live_…',
  environment: kDebugMode
      ? TapAppLinkEnvironment.sandbox
      : TapAppLinkEnvironment.production,
));

await TapAppLink.trackInstall();
await TapAppLink.setAppUserId(await Purchases.appUserID);
```

## License

MIT
