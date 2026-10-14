import 'dart:async';
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

/// Offer fields on a successful `/redeemCode` response.
///
/// Server fields are optional so older clients keep type-checking. Prefer
/// [TapAppLinkOffer] from [TapAppLink.getOffer] for the cached attribution offer.
class TapAppLinkRedeemOffer {
  const TapAppLinkRedeemOffer({
    this.creatorName,
    this.promoCode,
    this.billingOfferId,
  });

  final String? creatorName;
  final String? promoCode;
  final String? billingOfferId;

  Map<String, dynamic> toJson() => {
        if (creatorName != null) 'creatorName': creatorName,
        if (promoCode != null) 'promoCode': promoCode,
        if (billingOfferId != null) 'billingOfferId': billingOfferId,
      };

  static TapAppLinkRedeemOffer? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return TapAppLinkRedeemOffer(
      creatorName: json['creatorName'] as String?,
      promoCode: json['promoCode'] as String?,
      billingOfferId: json['billingOfferId'] as String?,
    );
  }
}

/// Success body from `/redeemCode`. New fields from the server are optional so
/// older clients keep type-checking.
class TapAppLinkRedeemResult {
  const TapAppLinkRedeemResult({
    this.attributionId,
    this.alreadyAttributed,
    this.codeMatches,
    this.offer,
  });

  final String? attributionId;
  final bool? alreadyAttributed;

  /// True when the submitted code matches the attributed creator offer.
  final bool? codeMatches;
  final TapAppLinkRedeemOffer? offer;

  Map<String, dynamic> toJson() => {
        if (attributionId != null) 'attributionId': attributionId,
        if (alreadyAttributed != null) 'alreadyAttributed': alreadyAttributed,
        if (codeMatches != null) 'codeMatches': codeMatches,
        if (offer != null) 'offer': offer!.toJson(),
      };

  factory TapAppLinkRedeemResult.fromJson(Map<String, dynamic> json) {
    final rawOffer = json['offer'];
    return TapAppLinkRedeemResult(
      attributionId: json['attributionId'] as String?,
      alreadyAttributed: json['alreadyAttributed'] as bool?,
      codeMatches: json['codeMatches'] as bool?,
      offer: rawOffer is Map
          ? TapAppLinkRedeemOffer.fromJson(
              Map<String, dynamic>.from(rawOffer),
            )
          : null,
    );
  }
}

/// Thrown by [TapAppLink.applyCode] when redeem fails.
///
/// Cases: [TapAppLinkUnknownCodeException], [TapAppLinkInactiveCodeException],
/// [TapAppLinkWrongEnvironmentException], [TapAppLinkNetworkException],
/// [TapAppLinkApplyCodeOtherException].
sealed class TapAppLinkApplyCodeException implements Exception {
  const TapAppLinkApplyCodeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The code was not recognised (HTTP 404, or body `error: unknown_code`).
final class TapAppLinkUnknownCodeException
    extends TapAppLinkApplyCodeException {
  const TapAppLinkUnknownCodeException([
    super.message = 'Unknown code',
  ]);
}

/// The code is no longer active (HTTP 410, or body `error: inactive_code`).
final class TapAppLinkInactiveCodeException
    extends TapAppLinkApplyCodeException {
  const TapAppLinkInactiveCodeException([
    super.message = 'Inactive code',
  ]);
}

/// The code belongs to the other environment (Sandbox or Production).
///
/// Show customers the same copy as [TapAppLinkUnknownCodeException]. Log
/// [developerWarning] for developers only; never show the word "environment"
/// to customers.
final class TapAppLinkWrongEnvironmentException
    extends TapAppLinkApplyCodeException {
  const TapAppLinkWrongEnvironmentException([
    super.message = 'Wrong environment',
  ]);

  /// Developer-only warning. Do not show this string to customers.
  static const String developerWarning =
      'This code belongs to the other environment (Sandbox or Production). '
      'Check your API key.';
}

/// Network failure or timeout while redeeming a code.
final class TapAppLinkNetworkException extends TapAppLinkApplyCodeException {
  const TapAppLinkNetworkException([
    super.message = 'Network error',
  ]);
}

/// Any other non-success redeem response.
final class TapAppLinkApplyCodeOtherException
    extends TapAppLinkApplyCodeException {
  const TapAppLinkApplyCodeOtherException({
    required this.status,
    required String message,
  }) : super(message);

  final int status;
}

class TapAppLink {
  TapAppLink._();

  /// Package / wire version sent as `X-TapAppLink-SDK-Version`.
  static const String sdkVersion = '0.3.3';

  static const MethodChannel _installReferrerChannel =
      MethodChannel('com.tapapplink/tapapplink');

  static const String _prefsInstallId = 'tapapplink.installId';
  static const String _prefsTracked = 'tapapplink.tracked';
  static const String _prefsAttributionId = 'tapapplink.attributionId';
  static const String _prefsOffer = 'tapapplink.offer';

  /// Last app user id that successfully completed `/ingestIdentify`.
  static const String _prefsAppUserId = 'tapapplink.appUserId';
  static const String _prefsPendingRedeemRequestId =
      'tapapplink.pendingRedeemRequestId';
  static const String _prefsPendingRedeemCode = 'tapapplink.pendingRedeemCode';

  static TapAppLinkConfig? _config;
  static bool _storageLoaded = false;
  static bool _tracked = false;
  static String? _installId;
  static String? _lastAttributionId;
  static String? _lastAppUserId;

  /// Last app user id that successfully completed `/ingestIdentify` (persisted).
  static String? _identifiedAppUserId;
  static TapAppLinkOffer? _lastOffer;
  static String? _pendingRedeemRequestId;
  static String? _pendingRedeemCode;

  /// Coalesce concurrent identical [setAppUserId] calls into one POST.
  static final Map<String, Future<Map<String, dynamic>>> _identifyInFlight =
      <String, Future<Map<String, dynamic>>>{};

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

  /// Links the billing user id via `/ingestIdentify`.
  ///
  /// Skips the network call when [appUserId] matches the last successfully
  /// identified value (persisted like the install tracked flag). Concurrent
  /// identical calls share one in-flight request. A different id still posts.
  static Future<Map<String, dynamic>> setAppUserId(String appUserId) async {
    await _ensureLoaded();
    _lastAppUserId = appUserId;

    if (_identifiedAppUserId == appUserId) {
      final skipped = <String, dynamic>{
        'skipped': true,
        'appUserId': appUserId,
        if (_lastAttributionId != null) 'attributionId': _lastAttributionId,
      };
      _log('setAppUserId skipped; already identified $skipped');
      return skipped;
    }

    final existing = _identifyInFlight[appUserId];
    if (existing != null) {
      _log(
          'setAppUserId coalesced with in-flight identify appUserId=$appUserId');
      return existing;
    }

    final future = () async {
      try {
        final result = await _post('/ingestIdentify', {
          'appUserId': appUserId,
          'attributionId': _lastAttributionId,
        });
        _identifiedAppUserId = appUserId;
        await _persistState();
        return result;
      } finally {
        _identifyInFlight.remove(appUserId);
      }
    }();

    _identifyInFlight[appUserId] = future;
    return future;
  }

  /// Redeems a creator code via `/redeemCode`.
  ///
  /// On success returns a [TapAppLinkRedeemResult] (may include
  /// `alreadyAttributed`, `codeMatches`, and `offer` with optional
  /// `creatorName`). On failure throws a [TapAppLinkApplyCodeException]
  /// subclass.
  ///
  /// Sends a stable `requestId` per normalised code attempt so the server can
  /// recognise retries after a timeout or app restart. Definitive responses
  /// (2xx, or unknown / inactive / wrong-environment) clear the pending id.
  static Future<TapAppLinkRedeemResult> applyCode(String code) async {
    await _ensureLoaded();
    final requestId = await _ensureRedeemRequestId(code);
    final platform = _platformName();
    try {
      final result = await _post('/redeemCode', {
        'code': code,
        'requestId': requestId,
        'appUserId': _lastAppUserId,
        'attributionId': _lastAttributionId,
        'platform': platform,
      });
      await _clearPendingRedeem();
      _cacheFromResult(result);
      await _persistState();
      return TapAppLinkRedeemResult.fromJson(result);
    } on TapAppLinkUnknownCodeException {
      await _clearPendingRedeem();
      rethrow;
    } on TapAppLinkInactiveCodeException {
      await _clearPendingRedeem();
      rethrow;
    } on TapAppLinkWrongEnvironmentException {
      await _clearPendingRedeem();
      rethrow;
    } on TapAppLinkApplyCodeException {
      // Network / other: keep the pending requestId for retry.
      rethrow;
    } on SocketException catch (error) {
      throw TapAppLinkNetworkException(error.message);
    } on TimeoutException catch (error) {
      throw TapAppLinkNetworkException(error.message ?? 'Request timed out');
    } on http.ClientException catch (error) {
      throw TapAppLinkNetworkException(error.message);
    } on HandshakeException catch (error) {
      throw TapAppLinkNetworkException(error.message);
    }
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
    _identifiedAppUserId = null;
    _lastOffer = null;
    _pendingRedeemRequestId = null;
    _pendingRedeemCode = null;
    _storageLoaded = false;
    _identifyInFlight.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsInstallId);
    await prefs.remove(_prefsTracked);
    await prefs.remove(_prefsAttributionId);
    await prefs.remove(_prefsOffer);
    await prefs.remove(_prefsAppUserId);
    await prefs.remove(_prefsPendingRedeemRequestId);
    await prefs.remove(_prefsPendingRedeemCode);
  }

  /// Clears memory only so the next call reloads from shared_preferences.
  @visibleForTesting
  static void debugClearMemory() {
    _tracked = false;
    _installId = null;
    _lastAttributionId = null;
    _lastAppUserId = null;
    _identifiedAppUserId = null;
    _lastOffer = null;
    _pendingRedeemRequestId = null;
    _pendingRedeemCode = null;
    _storageLoaded = false;
    _identifyInFlight.clear();
  }

  /// Pending redeem request id after a non-definitive attempt (test helper).
  @visibleForTesting
  static String? get debugPendingRedeemRequestId => _pendingRedeemRequestId;

  /// Normalises a redeem code: uppercase, strip non-alphanumerics, max 24.
  @visibleForTesting
  static String normaliseCodeForTesting(String code) => _normaliseCode(code);

  static Future<void> _ensureLoaded() async {
    if (_storageLoaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _installId = prefs.getString(_prefsInstallId);
    _tracked = prefs.getBool(_prefsTracked) ?? false;
    _lastAttributionId = prefs.getString(_prefsAttributionId);
    _identifiedAppUserId = prefs.getString(_prefsAppUserId);
    if (_identifiedAppUserId != null) {
      _lastAppUserId = _identifiedAppUserId;
    }
    _pendingRedeemRequestId = prefs.getString(_prefsPendingRedeemRequestId);
    _pendingRedeemCode = prefs.getString(_prefsPendingRedeemCode);
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
    final identifiedAppUserId = _identifiedAppUserId;
    if (identifiedAppUserId == null) {
      await prefs.remove(_prefsAppUserId);
    } else {
      await prefs.setString(_prefsAppUserId, identifiedAppUserId);
    }
    final offer = _lastOffer;
    if (offer == null) {
      await prefs.remove(_prefsOffer);
    } else {
      await prefs.setString(_prefsOffer, jsonEncode(offer.toJson()));
    }
    await _persistPendingRedeem(prefs);
  }

  static Future<void> _persistPendingRedeem(
      [SharedPreferences? existing]) async {
    final prefs = existing ?? await SharedPreferences.getInstance();
    final requestId = _pendingRedeemRequestId;
    final code = _pendingRedeemCode;
    if (requestId == null || code == null) {
      await prefs.remove(_prefsPendingRedeemRequestId);
      await prefs.remove(_prefsPendingRedeemCode);
    } else {
      await prefs.setString(_prefsPendingRedeemRequestId, requestId);
      await prefs.setString(_prefsPendingRedeemCode, code);
    }
  }

  /// Uppercase, strip non-alphanumerics, truncate to 24 characters.
  static String _normaliseCode(String code) {
    final cleaned = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length <= 24) {
      return cleaned;
    }
    return cleaned.substring(0, 24);
  }

  /// One requestId per normalised code until a definitive redeem response.
  static Future<String> _ensureRedeemRequestId(String code) async {
    final normalised = _normaliseCode(code);
    final existingId = _pendingRedeemRequestId;
    final existingCode = _pendingRedeemCode;
    if (existingId != null &&
        existingId.isNotEmpty &&
        existingCode == normalised) {
      return existingId;
    }
    final created = _generateInstallId();
    _pendingRedeemRequestId = created;
    _pendingRedeemCode = normalised;
    await _persistPendingRedeem();
    _log('pending redeem requestId=$created code=$normalised');
    return created;
  }

  static Future<void> _clearPendingRedeem() async {
    _pendingRedeemRequestId = null;
    _pendingRedeemCode = null;
    await _persistPendingRedeem();
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
      'X-TapAppLink-SDK-Version': sdkVersion,
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
      if (path == '/redeemCode') {
        throw _mapRedeemFailure(response.statusCode, response.body);
      }
      throw HttpException(
        'TapAppLink request failed (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  /// Maps redeem HTTP failures to typed [TapAppLinkApplyCodeException]s.
  ///
  /// Prefers the body `error` field (`unknown_code`, `inactive_code`,
  /// `wrong_environment`). Falls back to status: 404 unknown, 410 inactive.
  /// A 400 with `wrong_environment` is covered by the body mapping.
  @visibleForTesting
  static TapAppLinkApplyCodeException mapRedeemFailureForTesting(
    int status,
    String body,
  ) =>
      _mapRedeemFailure(status, body);

  static TapAppLinkApplyCodeException _mapRedeemFailure(
    int status,
    String body,
  ) {
    String? errorCode;
    String? serverMessage;
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final err = decoded['error'];
          if (err is String) {
            errorCode = err;
          }
          final msg = decoded['message'];
          if (msg is String) {
            serverMessage = msg;
          }
        }
      } on FormatException {
        // Body is not JSON; fall through to status mapping.
      }
    }

    switch (errorCode) {
      case 'unknown_code':
        return TapAppLinkUnknownCodeException(serverMessage ?? 'Unknown code');
      case 'inactive_code':
        return TapAppLinkInactiveCodeException(
          serverMessage ?? 'Inactive code',
        );
      case 'wrong_environment':
        return TapAppLinkWrongEnvironmentException(
          serverMessage ?? 'Wrong environment',
        );
    }

    if (status == 404) {
      return const TapAppLinkUnknownCodeException();
    }
    if (status == 410) {
      return const TapAppLinkInactiveCodeException();
    }
    // 400 + wrong_environment is handled via the body field above.
    return TapAppLinkApplyCodeOtherException(
      status: status,
      message: serverMessage ??
          (body.isNotEmpty ? body : 'TapAppLink request failed ($status)'),
    );
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
        'attributionId=$_lastAttributionId '
        'appUserId=$_lastAppUserId identifiedAppUserId=$_identifiedAppUserId '
        'offer=${_lastOffer?.toJson()} '
        'pendingRedeem=$_pendingRedeemCode/$_pendingRedeemRequestId';
  }

  static void _log(String message) {
    if (_config?.debug == true) {
      debugPrint('[TapAppLink] $message');
    }
  }
}
