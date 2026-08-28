import 'package:flutter/foundation.dart';
import 'package:tapapplink/tapapplink.dart';

Future<void> main() async {
  TapAppLink.configure(
    const TapAppLinkConfig(
      publicKey: 'etk_test_replace_me',
      environment: kDebugMode
          ? TapAppLinkEnvironment.sandbox
          : TapAppLinkEnvironment.production,
    ),
  );
  await TapAppLink.trackInstall();
}
