import 'package:flutter_test/flutter_test.dart';
import 'package:tapapplink_example/main.dart';

void main() {
  testWidgets('example app shows guidance text', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.textContaining('Configure a real SDK key'), findsOneWidget);
  });
}
