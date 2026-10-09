import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum TapAppLinkEnvironment { production, sandbox }

class TapAppLinkConfig {
  const TapAppLinkConfig({
    required this.publicKey,
    required this.environment,
    this.ingestUrl,
    this.debug = false,
  });

  final String publicKey;
  final TapAppLinkEnvironment environment;
  final String? ingestUrl;

  /// When true, logs each request, response and stored state (API key redacted).
  final bool debug;
}

class TapAppLinkOffer {
  const TapAppLinkOffer({
    required this.creatorName,
    this.promoCode,
    this.billingOfferId,
  });

  final String creatorName;
  final String? promoCode;
  final String? billingOfferId;

  Map<String, dynamic> toJson() => {
        'creatorName': creatorName,
        if (promoCode != null) 'promoCode': promoCode,
        if (billingOfferId != null) 'billingOfferId': billingOfferId,
      };

  static TapAppLinkOffer? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return TapAppLinkOffer(
      creatorName: json['creatorName'] as String? ?? '',
      promoCode: json['promoCode'] as String?,
      billingOfferId: json['billingOfferId'] as String?,
    );
  }
}

class TapAppLink {
  TapAppLink._();

  static const MethodChannel _installReferrerChannel =
      MethodChannel('com.tapapplink/tapapplink');

  static const String _prefsInstallId = 'tapapplink.installId';
  static const String _prefsTracked = 'tapapplink.tracked';
  static const String _prefsAttributionId = 'tapapplink.attributionId';
  static const String _prefsOffer = 'tapapplink.offer';
  static const String _prefsAppUserId = 'tapapplink.appUserId';

  static TapAppLinkConfig? _config;
  static bool _storageLoaded = false;
  static bool _tracked = false;
  static String? _installId;
  static String? _lastAttributionId;
  static String? _lastAppUserId;
  static TapAppLinkOffer? _lastOffer;

  /// Override for tests. When null, a real [http.Client] is used.
  @visibleForTesting
  static http.Client? debugHttpClient;

  /// Override Play Install Referrer (and the method channel) in tests.
  @visibleForTesting
  static Future<String?> Function()? debugInstallReferrerProvider;

  static void configure(TapAppLinkConfig next) {
    _config = next;
    _log('configure environment=${next.environment.name} debug=${next.debug}');
  }

  static Future<Map<String, dynamic>> trackInstall({
    String? installReferrer,
    Duration installReferrerTimeout = const Duration(seconds: 3),
  }) async {
    if (_config == null) {
      throw StateError('TapAppLink.configure() must be called first');
    }
    await _ensureLoaded();
    if (_tracked) {
      _log('trackInstall skipped; returning stored state');
      return _storedInstallResult(skipped: true);
    }

    final installId = await _ensureInstallId();
    final resolvedReferrer = installReferrer ??
        await _readInstallReferrer(timeout: installReferrerTimeout);

    final platform = _platformName();
    final result = await _post('/ingestInstall', {
      'platform': platform,
      'deviceFamily': Platform.isIOS ? 'iPhone' : 'Android',
      'locale': Platform.localeName,
      'networkContext': Platform.localeName.split('_').last,
      'installReferrer': resolvedReferrer,
      'installId': installId,
      'firstOpenAt': DateTime.now().toUtc().toIso8601String(),
    });

    _tracked = true;
    _cacheFromResult(result);
    await _persistState();
    _log('trackInstall stored ${_describeStoredState()}');
    return result;
  }

  static Future<Map<String, dynamic>> setAppUserId(String appUserId) async {
    await _ensureLoaded();
    _lastAppUserId = appUserId;
    await _persistState();
    return _post('/ingestIdentify', {
      'appUserId': appUserId,
      'attributionId': _lastAttributionId,
    });
  }

  static Future<Map<String, dynamic>> applyCode(String code) async {
    await _ensureLoaded();
    final platform = _platformName();
    final result = await _post('/redeemCode', {
      'code': code,
      'appUserId': _lastAppUserId,
      'attributionId': _lastAttributionId,
      'platform': platform,
    });
    _cacheFromResult(result);
    await _persistState();
    return result;
  }

  static TapAppLinkOffer? getOffer() => _lastOffer;

  static String? getAttributionId() => _lastAttributionId;

  static String? getAppUserId() => _lastAppUserId;

  static String? getInstallId() => _installId;

  static Future<Map<String, dynamic>> linkRevenueCatUser(String appUserId) =>
      setAppUserId(appUserId);

  static Future<Map<String, dynamic>> linkAdaptyUser(String customerUserId) =>
      setAppUserId(customerUserId);

  static Future<Map<String, dynamic>> linkSuperwallUser(String appUserId) =>
      setAppUserId(appUserId);

  static Future<Map<String, dynamic>> linkQonversionUser(String userId) =>
      setAppUserId(userId);

  /// Clears in-memory and persisted install state. Prefer in debug / test only.
  static Future<void> resetForTesting() async {
    _config = null;
    _tracked = false;
    _installId = null;
    _lastAttributionId = null;
    _lastAppUserId = null;
    _lastOffer = null;
    _storageLoaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsInstallId);
    await prefs.remove(_prefsTracked);
    await prefs.remove(_prefsAttributionId);
    await prefs.remove(_prefsOffer);
    await prefs.remove(_prefsAppUserId);
  }

  /// Clears memory only so the next call reloads from shared_preferences.
  @visibleForTesting
  static void debugClearMemory() {
    _tracked = false;
    _installId = null;
    _lastAttributionId = null;
    _lastAppUserId = null;
    _lastOffer = null;
    _storageLoaded = false;
  }

  static Future<void> _ensureLoaded() async {
    if (_storageLoaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _installId = prefs.getString(_prefsInstallId);
    _tracked = prefs.getBool(_prefsTracked) ?? false;
    _lastAttributionId = prefs.getString(_prefsAttributionId);
    _lastAppUserId = prefs.getString(_prefsAppUserId);
    final offerRaw = prefs.getString(_prefsOffer);
    if (offerRaw != null) {
      final decoded = jsonDecode(offerRaw);
      if (decoded is Map<String, dynamic>) {
        _lastOffer = TapAppLinkOffer.fromJson(decoded);
      }
    }
    _storageLoaded = true;
    _log('loaded stored state ${_describeStoredState()}');
  }

  static Future<String> _ensureInstallId() async {
    final existing = _installId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _generateInstallId();
    _installId = created;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsInstallId, created);
    _log('created installId=$created');
    return created;
  }

  static Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    final installId = _installId;
    if (installId != null) {
      await prefs.setString(_prefsInstallId, installId);
    }
    await prefs.setBool(_prefsTracked, _tracked);
    final attributionId = _lastAttributionId;
    if (attributionId == null) {
      await prefs.remove(_prefsAttributionId);
    } else {
      await prefs.setString(_prefsAttributionId, attributionId);
    }
    final appUserId = _lastAppUserId;
    if (appUserId == null) {
      await prefs.remove(_prefsAppUserId);
    } else {
      await prefs.setString(_prefsAppUserId, appUserId);
    }
    final offer = _lastOffer;
    if (offer == null) {
      await prefs.remove(_prefsOffer);
    } else {
      await prefs.setString(_prefsOffer, jsonEncode(offer.toJson()));
    }
  }

  static Map<String, dynamic> _storedInstallResult({required bool skipped}) {
    return {
      'matched': _lastOffer != null,
      'skipped': skipped,
      if (_installId != null) 'installId': _installId,
      if (_lastAttributionId != null) 'attributionId': _lastAttributionId,
      if (_lastOffer != null) 'offer': _lastOffer!.toJson(),
    };
  }

  static void _cacheFromResult(Map<String, dynamic> result) {
    final attributionId = result['attributionId'];
    if (attributionId is String) {
      _lastAttributionId = attributionId;
    }
    final offer = result['offer'];
    if (offer is Map) {
      _lastOffer = TapAppLinkOffer.fromJson(
        Map<String, dynamic>.from(offer),
      );
    }
  }

  static Future<String?> _readInstallReferrer({
    required Duration timeout,
  }) async {
    final override = debugInstallReferrerProvider;
    if (override != null) {
      return override();
    }
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final value = await _installReferrerChannel.invokeMethod<String>(
        'getInstallReferrer',
        {'timeoutMs': timeout.inMilliseconds},
      );
      return value;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      _log('install referrer unavailable: ${error.code}');
      return null;
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
    final base =
        (cfg.ingestUrl ?? 'https://us-central1-tapapplink.cloudfunctions.net')
            .replaceAll(RegExp(r'/$'), '');
    final payload = Map<String, dynamic>.from(body)
      ..removeWhere((key, value) => value == null);
    final uri = Uri.parse('$base$path');
    final headers = {
      'Authorization': 'Bearer ${cfg.publicKey}',
      'Content-Type': 'application/json',
    };
    _log('request $path body=${jsonEncode(payload)} auth=Bearer [redacted]');

    final client = debugHttpClient ?? http.Client();
    final ownedClient = debugHttpClient == null;
    late http.Response response;
    try {
      response = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );
    } finally {
      if (ownedClient) {
        client.close();
      }
    }

    _log('response $path status=${response.statusCode} body=${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'TapAppLink request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  static String _platformName() {
    if (Platform.isIOS) {
      return 'IOS';
    }
    if (Platform.isAndroid) {
      return 'ANDROID';
    }
    return 'UNKNOWN';
  }

  static String _generateInstallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-'
        '${b.substring(12, 16)}-${b.substring(16, 20)}-${b.substring(20)}';
  }

  static String _describeStoredState() {
    return 'tracked=$_tracked installId=$_installId '
        'attributionId=$_lastAttributionId appUserId=$_lastAppUserId '
        'offer=${_lastOffer?.toJson()}';
  }

  static void _log(String message) {
    if (_config?.debug == true) {
      debugPrint('[TapAppLink] $message');
    }
  }
}
