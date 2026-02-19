library appdna_sdk;

import 'dart:async';
import 'package:flutter/services.dart';
import 'models/web_entitlement.dart';
import 'models/deferred_deep_link.dart';
import 'models/paywall_context.dart';
import 'models/appdna_options.dart';
import 'billing.dart';

export 'models/web_entitlement.dart';
export 'models/deferred_deep_link.dart';
export 'models/paywall_context.dart';
export 'models/survey_result.dart';
export 'models/appdna_options.dart';
export 'billing.dart';
export 'push.dart';

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

  /// Set log verbosity level at runtime.
  /// Valid levels: 'none', 'error', 'warning', 'info', 'debug'.
  static void setLogLevel(String level) {
    _channel.invokeMethod('setLogLevel', {'level': level});
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

  /// Set push token. Registers with backend for direct push delivery.
  static Future<void> setPushToken(String token) async {
    await _channel.invokeMethod('setPushToken', {'token': token});
  }

  /// Report push permission status.
  static Future<void> setPushPermission(bool granted) async {
    await _channel.invokeMethod('setPushPermission', {'granted': granted});
  }

  /// Track push notification delivered (SPEC-030).
  static Future<void> trackPushDelivered(String pushId) async {
    await _channel.invokeMethod('trackPushDelivered', {'pushId': pushId});
  }

  /// Track push notification tapped (SPEC-030).
  static Future<void> trackPushTapped(String pushId, {String? action}) async {
    await _channel.invokeMethod('trackPushTapped', {
      'pushId': pushId,
      if (action != null) 'action': action,
    });
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

  // MARK: - v1.0 Module Namespaces

  /// Push notification module.
  static final push = AppDNAPushModule._(_channel);

  /// Onboarding module.
  static final onboarding = AppDNAOnboardingModule._(_channel);

  /// Paywall module.
  static final paywall = AppDNAPaywallModule._(_channel);

  /// Remote config module.
  static final remoteConfig = AppDNARemoteConfigModule._(_channel);

  /// Feature flags module.
  static final features = AppDNAFeaturesModule._(_channel);

  /// Experiments module.
  static final experiments = AppDNAExperimentsModule._(_channel);

  /// In-app messages module.
  static final inAppMessages = AppDNAInAppMessagesModule._(_channel);

  /// Surveys module.
  static final surveys = AppDNASurveysModule._(_channel);

  /// Deep links module.
  static final deepLinks = AppDNADeepLinksModule._(_channel);

  /// Billing module.
  static AppDNABilling billing = AppDNABilling();

  // MARK: - Lifecycle

  /// Shut down the SDK and release resources.
  /// On Android this delegates to AppDNA.shutdown(); on iOS this is a no-op.
  static Future<void> shutdown() async {
    await _channel.invokeMethod('shutdown');
  }

  /// Get the native SDK version string (e.g. "1.0.0").
  static Future<String> getSdkVersion() async {
    final version = await _channel.invokeMethod<String>('getSdkVersion');
    return version ?? 'unknown';
  }
}

// MARK: - Module Namespace Classes (v1.0)

/// Push notification module namespace.
class AppDNAPushModule {
  final MethodChannel _channel;
  AppDNAPushModule._(this._channel);

  Future<void> setToken(String token) => _channel.invokeMethod('setPushToken', {'token': token});
  Future<void> setPermission(bool granted) => _channel.invokeMethod('setPushPermission', {'granted': granted});
  Future<void> trackDelivered(String pushId) => _channel.invokeMethod('trackPushDelivered', {'pushId': pushId});
  Future<void> trackTapped(String pushId, {String? action}) =>
      _channel.invokeMethod('trackPushTapped', {'pushId': pushId, if (action != null) 'action': action});

  /// Request push notification permission from the OS.
  Future<bool> requestPermission() async {
    final result = await _channel.invokeMethod<bool>('requestPushPermission');
    return result ?? false;
  }

  /// Get the current push token.
  Future<String?> getToken() => _channel.invokeMethod<String>('getPushToken');

  /// Set a delegate to receive push notification callbacks.
  void setDelegate(AppDNAPushDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTokenRegistered':
          delegate.onTokenRegistered(call.arguments['token']);
          break;
        case 'onPushReceived':
          delegate.onPushReceived(Map<String, dynamic>.from(call.arguments));
          break;
        case 'onPushTapped':
          delegate.onPushTapped(Map<String, dynamic>.from(call.arguments));
          break;
      }
    });
  }
}

/// Onboarding module namespace.
class AppDNAOnboardingModule {
  final MethodChannel _channel;
  AppDNAOnboardingModule._(this._channel);

  Future<void> present(String flowId, {OnboardingContext? context}) =>
      _channel.invokeMethod('presentOnboarding', {'flowId': flowId, if (context != null) 'context': context.toMap()});

  /// Set a delegate to receive onboarding lifecycle callbacks.
  void setDelegate(AppDNAOnboardingDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onOnboardingStarted':
          delegate.onStarted(call.arguments['flowId']);
          break;
        case 'onOnboardingStepChanged':
          delegate.onStepChanged(call.arguments['flowId'], call.arguments['stepIndex']);
          break;
        case 'onOnboardingCompleted':
          delegate.onCompleted(call.arguments['flowId']);
          break;
        case 'onOnboardingDismissed':
          delegate.onDismissed(call.arguments['flowId']);
          break;
      }
    });
  }
}

/// Paywall module namespace.
class AppDNAPaywallModule {
  final MethodChannel _channel;
  AppDNAPaywallModule._(this._channel);

  Future<void> present(String id, {PaywallContext? context}) =>
      _channel.invokeMethod('presentPaywall', {'id': id, 'context': context?.toMap()});

  /// Set a delegate to receive paywall lifecycle callbacks.
  void setDelegate(AppDNAPaywallDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPaywallPresented':
          delegate.onPresented(call.arguments['paywallId']);
          break;
        case 'onPaywallAction':
          delegate.onAction(call.arguments['paywallId'], call.arguments['action']);
          break;
        case 'onPaywallPurchaseStarted':
          delegate.onPurchaseStarted(call.arguments['paywallId'], call.arguments['productId']);
          break;
        case 'onPaywallPurchaseCompleted':
          delegate.onPurchaseCompleted(call.arguments['paywallId'], call.arguments['productId']);
          break;
        case 'onPaywallPurchaseFailed':
          delegate.onPurchaseFailed(call.arguments['paywallId'], call.arguments['productId'], call.arguments['error']);
          break;
        case 'onPaywallDismissed':
          delegate.onDismissed(call.arguments['paywallId']);
          break;
      }
    });
  }
}

/// Remote config module namespace.
class AppDNARemoteConfigModule {
  final MethodChannel _channel;
  AppDNARemoteConfigModule._(this._channel);

  Future<dynamic> get(String key) => _channel.invokeMethod('getRemoteConfig', {'key': key});
  Future<void> refresh() => _channel.invokeMethod('refreshConfig');

  /// Get all remote config values as a map.
  Map<String, dynamic> getAll() {
    // Synchronous accessor for cached config values.
    // The native side maintains a local cache that is populated on configure/refresh.
    final Map<String, dynamic> result = {};
    _channel.invokeMethod<Map>('getAllRemoteConfig').then((data) {
      if (data != null) result.addAll(Map<String, dynamic>.from(data));
    });
    return result;
  }

  /// Register a callback to be notified when remote config values change.
  void onChanged(Function callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRemoteConfigChanged') {
        callback();
      }
    });
  }
}

/// Feature flags module namespace.
class AppDNAFeaturesModule {
  final MethodChannel _channel;
  AppDNAFeaturesModule._(this._channel);

  Future<bool> isEnabled(String flag) async {
    final result = await _channel.invokeMethod<bool>('isFeatureEnabled', {'flag': flag});
    return result ?? false;
  }

  /// Get the variant value for a feature flag (for multi-variate flags).
  dynamic getVariant(String flag) {
    return _channel.invokeMethod('getFeatureVariant', {'flag': flag});
  }

  /// Register a callback to be notified when feature flags change.
  void onChanged(Function callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFeatureFlagsChanged') {
        callback();
      }
    });
  }
}

/// Experiments module namespace.
class AppDNAExperimentsModule {
  final MethodChannel _channel;
  AppDNAExperimentsModule._(this._channel);

  Future<String?> getVariant(String experimentId) =>
      _channel.invokeMethod<String>('getExperimentVariant', {'experimentId': experimentId});
  Future<bool> isInVariant(String experimentId, String variantId) async {
    final result = await _channel.invokeMethod<bool>('isInVariant', {'experimentId': experimentId, 'variantId': variantId});
    return result ?? false;
  }

  /// Get all experiment exposures for the current user.
  List<Map<String, dynamic>> getExposures() {
    final List<Map<String, dynamic>> result = [];
    _channel.invokeMethod<List>('getExperimentExposures').then((data) {
      if (data != null) {
        result.addAll(data.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    });
    return result;
  }
}

/// In-app messages module namespace.
class AppDNAInAppMessagesModule {
  final MethodChannel _channel;
  AppDNAInAppMessagesModule._(this._channel);

  Future<void> suppressDisplay(bool suppress) => _channel.invokeMethod('suppressMessages', {'suppress': suppress});

  /// Set a delegate to receive in-app message lifecycle callbacks.
  void setDelegate(AppDNAInAppMessageDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMessageShown':
          delegate.onMessageShown(call.arguments['messageId']);
          break;
        case 'onMessageAction':
          delegate.onMessageAction(call.arguments['messageId'], call.arguments['action']);
          break;
        case 'onMessageDismissed':
          delegate.onMessageDismissed(call.arguments['messageId']);
          break;
        case 'shouldShowMessage':
          return delegate.shouldShowMessage(call.arguments['messageId']);
      }
    });
  }
}

/// Surveys module namespace.
class AppDNASurveysModule {
  final MethodChannel _channel;
  AppDNASurveysModule._(this._channel);

  Future<void> present(String surveyId) => _channel.invokeMethod('presentSurvey', {'surveyId': surveyId});

  /// Set a delegate to receive survey lifecycle callbacks.
  void setDelegate(AppDNASurveyDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSurveyPresented':
          delegate.onSurveyPresented(call.arguments['surveyId']);
          break;
        case 'onSurveyCompleted':
          delegate.onSurveyCompleted(call.arguments['surveyId'], Map<String, dynamic>.from(call.arguments['responses']));
          break;
        case 'onSurveyDismissed':
          delegate.onSurveyDismissed(call.arguments['surveyId']);
          break;
      }
    });
  }
}

/// Deep links module namespace.
class AppDNADeepLinksModule {
  final MethodChannel _channel;
  AppDNADeepLinksModule._(this._channel);

  Future<void> handleURL(String url) => _channel.invokeMethod('handleDeepLink', {'url': url});

  /// Set a delegate to receive deep link callbacks.
  void setDelegate(AppDNADeepLinkDelegate delegate) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLinkReceived') {
        delegate.onDeepLinkReceived(
          call.arguments['url'],
          call.arguments['params'] != null
              ? Map<String, String>.from(call.arguments['params'])
              : null,
        );
      }
    });
  }
}

/// Context passed to onboarding flows.
class OnboardingContext {
  final String? source;
  final String? campaign;
  final String? referrer;
  final Map<String, dynamic>? userProperties;
  final Map<String, String>? experimentOverrides;

  const OnboardingContext({this.source, this.campaign, this.referrer, this.userProperties, this.experimentOverrides});

  Map<String, dynamic> toMap() => {
    if (source != null) 'source': source,
    if (campaign != null) 'campaign': campaign,
    if (referrer != null) 'referrer': referrer,
    if (userProperties != null) 'userProperties': userProperties,
    if (experimentOverrides != null) 'experimentOverrides': experimentOverrides,
  };
}

// MARK: - Delegate Abstract Classes (SPEC-041)

/// Delegate for onboarding lifecycle events.
abstract class AppDNAOnboardingDelegate {
  void onStarted(String flowId);
  void onStepChanged(String flowId, int stepIndex);
  void onCompleted(String flowId);
  void onDismissed(String flowId);
}

/// Delegate for paywall lifecycle events.
abstract class AppDNAPaywallDelegate {
  void onPresented(String paywallId);
  void onAction(String paywallId, String action);
  void onPurchaseStarted(String paywallId, String productId);
  void onPurchaseCompleted(String paywallId, String productId);
  void onPurchaseFailed(String paywallId, String productId, String error);
  void onDismissed(String paywallId);
}

/// Delegate for push notification events.
abstract class AppDNAPushDelegate {
  void onTokenRegistered(String token);
  void onPushReceived(Map<String, dynamic> payload);
  void onPushTapped(Map<String, dynamic> payload);
}

/// Delegate for billing events.
abstract class AppDNABillingDelegate {
  void onPurchaseCompleted(String productId);
  void onPurchaseFailed(String productId, String error);
  void onEntitlementsChanged(List<Map<String, dynamic>> entitlements);
  void onRestoreCompleted(List<Map<String, dynamic>> entitlements);
}

/// Delegate for in-app message events.
abstract class AppDNAInAppMessageDelegate {
  void onMessageShown(String messageId);
  void onMessageAction(String messageId, String action);
  void onMessageDismissed(String messageId);
  bool shouldShowMessage(String messageId);
}

/// Delegate for survey events.
abstract class AppDNASurveyDelegate {
  void onSurveyPresented(String surveyId);
  void onSurveyCompleted(String surveyId, Map<String, dynamic> responses);
  void onSurveyDismissed(String surveyId);
}

/// Delegate for deep link events.
abstract class AppDNADeepLinkDelegate {
  void onDeepLinkReceived(String url, Map<String, String>? params);
}
