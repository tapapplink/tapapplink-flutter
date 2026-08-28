import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tapapplink/tapapplink.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TapAppLink.configure(
    const TapAppLinkConfig(
      publicKey: 'etk_test_replace_me',
      environment: kDebugMode
          ? TapAppLinkEnvironment.sandbox
          : TapAppLinkEnvironment.production,
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Tap App Link')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Configure a real SDK key, then call TapAppLink.trackInstall(). '
            'The full device demo lives in the Tap App Link monorepo.',
          ),
        ),
      ),
    );
  }
}
