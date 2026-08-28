import 'package:flutter_test/flutter_test.dart';
import 'package:tapapplink/tapapplink.dart';

void main() {
  test('getters are null before configure', () {
    TapAppLink.resetForTesting();
    expect(TapAppLink.getOffer(), isNull);
    expect(TapAppLink.getAttributionId(), isNull);
    expect(TapAppLink.getAppUserId(), isNull);
  });
}
