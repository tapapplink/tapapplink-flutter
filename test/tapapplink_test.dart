import 'package:flutter_test/flutter_test.dart';
import 'package:tapapplink/tapapplink.dart';

void main() {
  setUp(TapAppLink.resetForTesting);

  test('getters are null after resetForTesting', () {
    expect(TapAppLink.getOffer(), isNull);
    expect(TapAppLink.getAttributionId(), isNull);
    expect(TapAppLink.getAppUserId(), isNull);
  });

  test('TapAppLinkConfig holds publicKey, environment, and ingestUrl', () {
    const config = TapAppLinkConfig(
      publicKey: 'etk_test',
      environment: TapAppLinkEnvironment.sandbox,
      ingestUrl: 'https://example.invalid',
    );
    expect(config.publicKey, 'etk_test');
    expect(config.environment, TapAppLinkEnvironment.sandbox);
    expect(config.ingestUrl, 'https://example.invalid');
  });

  test('TapAppLinkOffer stores creator and optional billing fields', () {
    const offer = TapAppLinkOffer(
      creatorName: 'Sarah',
      promoCode: 'SARAH10',
      billingOfferId: 'offer_1',
    );
    expect(offer.creatorName, 'Sarah');
    expect(offer.promoCode, 'SARAH10');
    expect(offer.billingOfferId, 'offer_1');
  });
}
