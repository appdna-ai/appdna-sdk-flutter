library appdna_sdk;

import 'dart:async';
import 'package:flutter/services.dart';
import 'models/web_entitlement.dart';
import 'models/deferred_deep_link.dart';
import 'models/paywall_context.dart';
import 'models/appdna_options.dart';

export 'models/web_entitlement.dart';
export 'models/deferred_deep_link.dart';
export 'models/paywall_context.dart';
export 'models/survey_result.dart';
export 'models/appdna_options.dart';

enum AppDNAEnvironment { production, staging }

/// Main entry point for the AppDNA Flutter SDK.
/// Thin wrapper around native iOS/Android SDKs via platform channels.
class AppDNA {
  static const MethodChannel _channel = MethodChannel('com.appdna.sdk/main');
  static const EventChannel _webEntitlementChannel =
      EventChannel('com.appdna.sdk/web_entitlement');

  /// Initialize the SDK. Call once at app startup.
  static Future<void> configure({
    required String apiKey,
    AppDNAEnvironment env = AppDNAEnvironment.production,
    AppDNAOptions? options,
  }) async {
    await _channel.invokeMethod('configure', {
      'apiKey': apiKey,
      'env': env.name,
      if (options != null) 'options': options.toMap(),
    });
  }

  /// Identify a user.
  static Future<void> identify(String userId,
      {Map<String, dynamic>? traits}) async {
    await _channel.invokeMethod('identify', {
      'userId': userId,
      'traits': traits,
    });
  }

  /// Clear user identity.
  static Future<void> reset() async {
    await _channel.invokeMethod('reset');
  }

  /// Track a custom event.
  static Future<void> track(String event,
      {Map<String, dynamic>? properties}) async {
    await _channel.invokeMethod('track', {
      'event': event,
      'properties': properties,
    });
  }

  /// Force flush all queued events.
  static Future<void> flush() async {
    await _channel.invokeMethod('flush');
  }

  /// Present a paywall.
  static Future<void> presentPaywall(String id,
      {PaywallContext? context}) async {
    await _channel.invokeMethod('presentPaywall', {
      'id': id,
      'context': context?.toMap(),
    });
  }

  /// Present an onboarding flow.
  static Future<void> presentOnboarding(String flowId) async {
    await _channel.invokeMethod('presentOnboarding', {'flowId': flowId});
  }

  /// Get a remote config value by key.
  static Future<dynamic> getRemoteConfig(String key) async {
    return await _channel.invokeMethod('getRemoteConfig', {'key': key});
  }

  /// Check if a feature flag is enabled.
  static Future<bool> isFeatureEnabled(String flag) async {
    final result =
        await _channel.invokeMethod<bool>('isFeatureEnabled', {'flag': flag});
    return result ?? false;
  }

  /// Get the variant assignment for an experiment.
  static Future<String?> getExperimentVariant(String experimentId) async {
    return await _channel.invokeMethod<String>(
        'getExperimentVariant', {'experimentId': experimentId});
  }

  /// Check if the user is in a specific variant.
  static Future<bool> isInVariant(
      String experimentId, String variantId) async {
    final result = await _channel.invokeMethod<bool>('isInVariant', {
      'experimentId': experimentId,
      'variantId': variantId,
    });
    return result ?? false;
  }

  /// Get experiment config value.
  static Future<dynamic> getExperimentConfig(
      String experimentId, String key) async {
    return await _channel.invokeMethod('getExperimentConfig', {
      'experimentId': experimentId,
      'key': key,
    });
  }

  /// Set push token.
  static Future<void> setPushToken(String token) async {
    await _channel.invokeMethod('setPushToken', {'token': token});
  }

  /// Report push permission status.
  static Future<void> setPushPermission(bool granted) async {
    await _channel.invokeMethod('setPushPermission', {'granted': granted});
  }

  /// Set analytics consent.
  static Future<void> setConsent({required bool analytics}) async {
    await _channel.invokeMethod('setConsent', {'analytics': analytics});
  }

  /// Register a ready callback.
  static Future<void> onReady(void Function() callback) async {
    final result = await _channel.invokeMethod<bool>('onReady');
    if (result == true) callback();
  }

  // MARK: - v0.3: Web Entitlements

  /// Get the current web subscription entitlement.
  static Future<WebEntitlement?> get webEntitlement async {
    final data = await _channel.invokeMethod<Map>('getWebEntitlement');
    if (data == null) return null;
    return WebEntitlement.fromMap(Map<String, dynamic>.from(data));
  }

  /// Listen for web entitlement changes.
  static Stream<WebEntitlement?> get onWebEntitlementChanged {
    return _webEntitlementChannel.receiveBroadcastStream().map((data) {
      if (data == null) return null;
      return WebEntitlement.fromMap(Map<String, dynamic>.from(data as Map));
    });
  }

  // MARK: - v0.3: Deferred Deep Links

  /// Check for a deferred deep link on first launch.
  static Future<DeferredDeepLink?> checkDeferredDeepLink() async {
    final data = await _channel.invokeMethod<Map>('checkDeferredDeepLink');
    if (data == null) return null;
    return DeferredDeepLink.fromMap(Map<String, dynamic>.from(data));
  }

  // MARK: - Lifecycle

  /// Shut down the SDK and release resources.
  /// On Android this delegates to AppDNA.shutdown(); on iOS this is a no-op.
  static Future<void> shutdown() async {
    await _channel.invokeMethod('shutdown');
  }

  /// Get the native SDK version string (e.g. "0.3.0").
  static Future<String> getSdkVersion() async {
    final version = await _channel.invokeMethod<String>('getSdkVersion');
    return version ?? 'unknown';
  }
}
