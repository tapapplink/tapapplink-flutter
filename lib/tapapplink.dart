import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum TapAppLinkEnvironment { production, sandbox }

class TapAppLinkConfig {
  const TapAppLinkConfig({
    required this.publicKey,
    required this.environment,
    this.ingestUrl,
    this.debugSessionId,
  });

  final String publicKey;
  final TapAppLinkEnvironment environment;
  final String? ingestUrl;
  final String? debugSessionId;
}

class TapAppLinkOffer {
  const TapAppLinkOffer({
    required this.creatorName,
    this.promoCode,
    required this.discountBps,
    this.billingOfferId,
  });

  final String creatorName;
  final String? promoCode;
  final int discountBps;
  final String? billingOfferId;
}

class TapAppLink {
  TapAppLink._();

  static TapAppLinkConfig? _config;
  static bool _tracked = false;
  static String? _lastAttributionId;
  static String? _lastAppUserId;
  static TapAppLinkOffer? _lastOffer;

  static void configure(TapAppLinkConfig next) {
    _config = next;
  }

  static Future<Map<String, dynamic>> trackInstall({
    String? installReferrer,
  }) async {
    if (_tracked) {
      return {'matched': false, 'skipped': true};
    }
    final platform = Platform.isIOS
        ? 'IOS'
        : Platform.isAndroid
            ? 'ANDROID'
            : 'UNKNOWN';
    final result = await _post('/ingestInstall', {
      'platform': platform,
      'deviceFamily': Platform.isIOS ? 'iPhone' : 'Android',
      'locale': Platform.localeName,
      'networkContext': Platform.localeName.split('_').last,
      'installReferrer': installReferrer,
      'firstOpenAt': DateTime.now().toUtc().toIso8601String(),
      'debugSessionId': _config?.debugSessionId,
    });
    _tracked = true;
    _cacheFromResult(result);
    return result;
  }

  static Future<Map<String, dynamic>> setAppUserId(String appUserId) {
    _lastAppUserId = appUserId;
    return _post('/ingestIdentify', {
      'appUserId': appUserId,
      'attributionId': _lastAttributionId,
      'debugSessionId': _config?.debugSessionId,
    });
  }

  static Future<Map<String, dynamic>> applyCode(String code) async {
    final platform = Platform.isIOS
        ? 'IOS'
        : Platform.isAndroid
            ? 'ANDROID'
            : 'UNKNOWN';
    final result = await _post('/redeemCode', {
      'code': code,
      'appUserId': _lastAppUserId,
      'attributionId': _lastAttributionId,
      'platform': platform,
      'debugSessionId': _config?.debugSessionId,
    });
    _cacheFromResult(result);
    return result;
  }

  static TapAppLinkOffer? getOffer() => _lastOffer;

  static String? getAttributionId() => _lastAttributionId;

  static String? getAppUserId() => _lastAppUserId;

  static Future<Map<String, dynamic>> linkRevenueCatUser(String appUserId) =>
      setAppUserId(appUserId);

  static Future<Map<String, dynamic>> linkAdaptyUser(String customerUserId) =>
      setAppUserId(customerUserId);

  static Future<Map<String, dynamic>> linkSuperwallUser(String appUserId) =>
      setAppUserId(appUserId);

  static Future<Map<String, dynamic>> linkQonversionUser(String userId) =>
      setAppUserId(userId);

  static void resetForTesting() {
    _tracked = false;
    _lastAttributionId = null;
    _lastAppUserId = null;
    _lastOffer = null;
  }

  static void _cacheFromResult(Map<String, dynamic> result) {
    final attributionId = result['attributionId'];
    if (attributionId is String) {
      _lastAttributionId = attributionId;
    }
    final offer = result['offer'];
    if (offer is Map<String, dynamic>) {
      _lastOffer = TapAppLinkOffer(
        creatorName: offer['creatorName'] as String? ?? '',
        promoCode: offer['promoCode'] as String?,
        discountBps: offer['discountBps'] as int? ?? 0,
        billingOfferId: offer['billingOfferId'] as String?,
      );
    }
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final cfg = _config;
    if (cfg == null) {
      throw StateError('TapAppLink.configure() must be called first');
    }
    final base = (cfg.ingestUrl ??
            'https://us-central1-tapapplink.cloudfunctions.net')
        .replaceAll(RegExp(r'/$'), '');
    final payload = Map<String, dynamic>.from(body)
      ..removeWhere((key, value) => value == null);
    final response = await http.post(
      Uri.parse('$base$path'),
      headers: {
        'Authorization': 'Bearer ${cfg.publicKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'TapAppLink request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }
}
