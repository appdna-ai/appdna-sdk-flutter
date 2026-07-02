library appdna_sdk;

import 'dart:async';
import 'package:flutter/services.dart';
import 'generated/delegates.dart';
import 'models/web_entitlement.dart';
import 'models/deferred_deep_link.dart';
import 'models/paywall_context.dart';
import 'models/appdna_options.dart';
import 'models/location_data.dart';
import 'billing.dart';

export 'models/web_entitlement.dart';
export 'models/deferred_deep_link.dart';
export 'models/paywall_context.dart';
export 'models/survey_result.dart';
export 'models/appdna_options.dart';
export 'models/location_data.dart';
export 'billing.dart';
export 'push.dart';

// SPEC-070-C Phase 2b — inline server-driven screen slot widget. Hosts the
// native AppDNAScreenSlot (SwiftUI / Compose) as a Flutter platform view.
export 'screen_slot.dart';

// Generated delegate interfaces are the canonical public API (SPEC-070-0).
// These supersede the previously hand-written abstract classes that lived
// at the bottom of this file. Customer code that implemented the old
// classes continues to work because the generated ones are supersets.
export 'generated/delegates.dart';

// Generated DTOs. The `AppDNAEnvironment` DTO class collides with the
// legacy `AppDNAEnvironment` enum below (kept for `AppDNA.configure(env:)`
// backwards-compatibility), so we hide it from the public surface here.
// Once consumers migrate off the enum, the hide clause can be dropped and
// the enum renamed.
export 'generated/dtos.dart' hide AppDNAEnvironment;

enum AppDNAEnvironment { production, staging }

/// Main entry point for the AppDNA Flutter SDK.
/// Thin wrapper around native iOS/Android SDKs via platform channels.
class AppDNA {
  static const MethodChannel _channel = MethodChannel('com.appdna.sdk/main');
  static const EventChannel _webEntitlementChannel =
      EventChannel('com.appdna.sdk/web_entitlement');

  /// Initialize the SDK. Call once at app startup.
  /// SPEC-070-C §5 — bidirectional sync-callback channel. Native invokes Dart on
  /// this channel for async return-value hooks + host-veto decisions and awaits the
  /// reply (the MethodChannel reply IS the correlation; native applies a
  /// timeout-default so a slow/absent host never deadlocks).
  static const MethodChannel _syncChannel =
      MethodChannel('com.appdna.sdk/sync_callbacks');
  static bool _syncCallbacksWired = false;

  /// SPEC-070-C §3.1 — Android-only init-degradation delegate stream. Native
  /// emits `onInitDegraded` here when `configure()` completes in a degraded
  /// state. iOS has no equivalent (documented no-op: the stream never emits).
  static const EventChannel _initChannel =
      EventChannel('com.appdna.sdk/events/init');
  static AppDNAInitDelegate? _initDelegate;
  static StreamSubscription? _initSub;

  static void _ensureSyncCallbacks() {
    if (_syncCallbacksWired) return;
    _syncCallbacksWired = true;
    _syncChannel.setMethodCallHandler(_handleSyncCallback);
  }

  /// Dispatches a native sync-callback to the registered host delegate and returns
  /// its result (Future for the async onboarding hooks; bool for the vetos). Returns
  /// the SDK's default when no delegate is registered so native proceeds normally.
  static Future<dynamic> _handleSyncCallback(MethodCall call) async {
    final args =
        (call.arguments as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    String s(String k) => args[k] as String? ?? '';
    int i(String k) => (args[k] as num?)?.toInt() ?? 0;
    Map<String, dynamic> m(String k) =>
        (args[k] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    switch (call.method) {
      // ── Onboarding async return-value hooks (Phase 2a) ───────────────────
      case 'onBeforeStepAdvance':
        return await onboarding._delegate?.onBeforeStepAdvance(
          s('flowId'), s('fromStepId'), i('stepIndex'), s('stepType'),
          m('responses'), (args['stepData'] as Map?)?.cast<String, dynamic>(),
        );
      case 'onBeforeStepRender':
        return await onboarding._delegate?.onBeforeStepRender(
          s('flowId'), s('stepId'), i('stepIndex'), s('stepType'), m('responses'),
        );
      case 'onElementInteraction':
        return await onboarding._delegate?.onElementInteraction(
          s('flowId'), s('stepId'), s('blockId'), s('action'),
          args['value'] as String?, m('inputValues'),
        );
      case 'onPermissionRequest':
        return await onboarding._delegate?.onPermissionRequest(s('permissionType'));
      // ── Host-veto decisions (D10; native seams land in Phase 2b) ─────────
      case 'shouldShowMessage':
        return inAppMessages._delegate?.shouldShowMessage(s('messageId')) ?? true;
      case 'onScreenAction':
        return screen._delegate?.onScreenAction(s('screenId'), m('action')) ?? true;
      case 'shouldOpen':
        return deepLinks._delegate?.shouldOpen(s('url'), m('params')) ?? true;
      default:
        return null;
    }
  }

  static Future<void> configure({
    required String apiKey,
    AppDNAEnvironment env = AppDNAEnvironment.production,
    AppDNAOptions? options,
  }) async {
    _ensureSyncCallbacks();
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

  /// Screen (server-driven UI) module.
  static final screen = AppDNAScreenModule._(_channel);

  /// Billing module.
  static AppDNABilling billing = AppDNABilling();

  // MARK: - Lifecycle

  /// Shut down the SDK and release resources.
  /// On Android this delegates to AppDNA.shutdown(); on iOS this is a no-op.
  static Future<void> shutdown() async {
    await _channel.invokeMethod('shutdown');
  }

  /// Get the native SDK version string (e.g. iOS "1.0.61" or Android "1.0.33").
  static Future<String> getSdkVersion() async {
    final version = await _channel.invokeMethod<String>('getSdkVersion');
    return version ?? 'unknown';
  }

  // MARK: - SPEC-070-C §3.1 lifecycle / core (full native parity)

  /// Register background tasks (iOS `BGTaskScheduler` event-upload / Android
  /// WorkManager). Call once at startup after `configure`. Real on both.
  static Future<void> registerBackgroundTasks() async {
    await _channel.invokeMethod('registerBackgroundTasks');
  }

  /// Whether analytics consent is currently granted.
  static Future<bool> isConsentGranted() async {
    final granted = await _channel.invokeMethod<bool>('isConsentGranted');
    return granted ?? false;
  }

  /// Emit a comprehensive SDK health report. Returns the report string on
  /// Android; on iOS the report is printed to the console and this returns
  /// `null` (§3.1: iOS `diagnose()` is `Void`).
  static Future<String?> diagnose() async {
    return await _channel.invokeMethod<String>('diagnose');
  }

  /// Get the identified user's traits (empty map if none / not identified).
  static Future<Map<String, dynamic>> getUserTraits() async {
    final data = await _channel.invokeMethod<Map>('getUserTraits');
    return data == null ? {} : Map<String, dynamic>.from(data);
  }

  /// Force a forced-theme override. Valid values: `'light'`, `'dark'`,
  /// `'system'`, or `null` to follow the system. **Android-only** — a
  /// documented no-op on iOS (§3.14).
  static Future<void> setForcedTheme(String? theme) async {
    await _channel.invokeMethod('setForcedTheme', {'theme': theme});
  }

  /// Read the current forced-theme override (`'light'`/`'dark'`/`'system'`),
  /// or `null` when following the system. **Android-only** — always returns
  /// `null` on iOS (§3.14).
  static Future<String?> getForcedTheme() async {
    return await _channel.invokeMethod<String>('getForcedTheme');
  }

  /// Register a delegate notified when `configure()` completes in a degraded
  /// state (`onInitDegraded`). **Android-only** — on iOS the underlying stream
  /// never emits (§3.14). Pass `null` to clear.
  static void setInitDelegate(AppDNAInitDelegate? delegate) {
    _initDelegate = delegate;
    _initSub?.cancel();
    _initSub = null;
    if (delegate == null) return;
    _initSub = _initChannel.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      final type = raw['type'] as String?;
      final args =
          (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (type == 'onInitDegraded') {
        _initDelegate?.onInitDegraded(
          (args['error'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
      }
    });
  }

  /// The last init error captured during `configure()` as a `{message, type}`
  /// map, or `null` if init succeeded. **Android-only** — returns `null` on
  /// iOS (§3.14).
  static Future<Map<String, dynamic>?> lastInitError() async {
    final data = await _channel.invokeMethod<Map>('getLastInitError');
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  // MARK: - SPEC-070-C §3.2 events

  /// Feed the current screen name so subsequent events carry `context.screen`
  /// (zero-code screen attribution). **Android-only** — a no-op on iOS (§3.14).
  static Future<void> notifyScreenAppeared(String screenName) async {
    await _channel.invokeMethod('notifyScreenAppeared', {'screenName': screenName});
  }

  // MARK: - SPEC-070-C §3.3 config

  /// Force an immediate remote-config refresh from the backend.
  static Future<void> forceRefreshConfig() async {
    await _channel.invokeMethod('forceRefreshConfig');
  }

  /// The applied config version for debugging. Pass a [flowId] to scope to a
  /// specific onboarding flow. Returns `null` when no config is applied yet.
  static Future<int?> debugAppliedConfigVersion({String? flowId}) async {
    final v = await _channel.invokeMethod<int>(
        'debugAppliedConfigVersion', {'flowId': flowId});
    return v;
  }

  // MARK: - SPEC-070-C §3.7 paywall

  /// Present a paywall by placement — the SDK auto-selects the best audience
  /// match. Real on Android; on iOS this routes to the placement-based
  /// `presentPaywall` overload (§3.14).
  static Future<void> presentPaywallByPlacement(String placement,
      {PaywallContext? context}) async {
    await _channel.invokeMethod('presentPaywallByPlacement', {
      'placement': placement,
      'context': context?.toMap(),
    });
  }

  /// Shorthand to present a paywall by ID over the current top screen.
  static Future<void> showPaywall(String id) async {
    await _channel.invokeMethod('showPaywall', {'id': id});
  }

  /// Suppress the next auto-dismiss that would otherwise fire after a restore
  /// completes (so the host can present its own post-restore UX).
  static Future<void> skipNextAutoDismissOnRestore(bool value) async {
    await _channel
        .invokeMethod('skipNextAutoDismissOnRestore', {'value': value});
  }

  // MARK: - SPEC-070-C §3.9 surveys

  /// Shorthand to present a survey by ID.
  static Future<void> showSurvey(String id) async {
    await _channel.invokeMethod('showSurvey', {'id': id});
  }
}

/// SPEC-070-C §3.1 — delegate notified when the SDK finishes `configure()` in
/// a degraded state (e.g. Firebase unavailable). **Android-only**; on iOS the
/// backing stream never emits. Register via [AppDNA.setInitDelegate].
abstract class AppDNAInitDelegate {
  /// Called with a `{message, type}` map describing the degraded-init reason.
  void onInitDegraded(Map<String, dynamic> error);
}

// MARK: - Module Namespace Classes (v1.0)
//
// Each module that owns a delegate listens on a dedicated EventChannel under
// `com.appdna.sdk/events/<name>`. Native (iOS Swift + Android Kotlin) sinks
// emit a `{ type: <delegateMethodName>, args: { ... } }` envelope. Dart
// dispatches each envelope to the typed delegate method on the
// customer-set delegate. Unknown `type` values are ignored silently so new
// native events ship without forcing a Flutter package bump.

/// Push notification module namespace.
class AppDNAPushModule {
  final MethodChannel _channel;
  AppDNAPushDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/push');

  AppDNAPushModule._(this._channel);

  Future<void> setToken(String token) =>
      _channel.invokeMethod('setPushToken', {'token': token});
  Future<void> setPermission(bool granted) =>
      _channel.invokeMethod('setPushPermission', {'granted': granted});
  Future<void> trackDelivered(String pushId) =>
      _channel.invokeMethod('trackPushDelivered', {'pushId': pushId});
  Future<void> trackTapped(String pushId, {String? action}) =>
      _channel.invokeMethod('trackPushTapped',
          {'pushId': pushId, if (action != null) 'action': action});

  /// Request push notification permission from the OS.
  Future<bool> requestPermission() async {
    final result = await _channel.invokeMethod<bool>('requestPushPermission');
    return result ?? false;
  }

  /// Get the current push token.
  Future<String?> getToken() => _channel.invokeMethod<String>('getPushToken');

  /// Set a delegate to receive push notification callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNAPushDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onPushTokenRegistered':
        d.onPushTokenRegistered(args['token'] as String? ?? '');
        break;
      case 'onPushReceived':
        d.onPushReceived(
          (args['notification'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
          args['inForeground'] as bool? ?? false,
        );
        break;
      case 'onPushTapped':
        d.onPushTapped(
          (args['notification'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
          args['actionId'] as String?,
        );
        break;
      default:
        // Unknown event — forward-compat with future native methods.
        break;
    }
  }
}

/// Onboarding module namespace.
class AppDNAOnboardingModule {
  final MethodChannel _channel;
  AppDNAOnboardingDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/onboarding');

  AppDNAOnboardingModule._(this._channel);

  Future<void> present(String flowId, {OnboardingContext? context}) =>
      _channel.invokeMethod('presentOnboarding', {
        'flowId': flowId,
        if (context != null) 'context': context.toMap(),
      });

  /// Set a delegate to receive onboarding lifecycle callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNAOnboardingDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onOnboardingStarted':
        d.onOnboardingStarted(args['flowId'] as String? ?? '');
        break;
      case 'onOnboardingStepChanged':
        d.onOnboardingStepChanged(
          args['flowId'] as String? ?? '',
          args['stepId'] as String? ?? '',
          (args['stepIndex'] as num?)?.toInt() ?? 0,
          (args['totalSteps'] as num?)?.toInt() ?? 0,
        );
        break;
      case 'onOnboardingCompleted':
        d.onOnboardingCompleted(
          args['flowId'] as String? ?? '',
          (args['responses'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      case 'onOnboardingDismissed':
        d.onOnboardingDismissed(
          args['flowId'] as String? ?? '',
          (args['atStep'] as num?)?.toInt() ?? 0,
        );
        break;
      default:
        break;
    }
  }
}

/// Paywall module namespace.
class AppDNAPaywallModule {
  final MethodChannel _channel;
  AppDNAPaywallDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/paywall');

  AppDNAPaywallModule._(this._channel);

  Future<void> present(String id, {PaywallContext? context}) =>
      _channel.invokeMethod(
          'presentPaywall', {'id': id, 'context': context?.toMap()});

  /// Set a delegate to receive paywall lifecycle callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNAPaywallDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onPaywallPresented':
        d.onPaywallPresented(args['paywallId'] as String? ?? '');
        break;
      case 'onPaywallAction':
        d.onPaywallAction(
          args['paywallId'] as String? ?? '',
          args['action'] as String? ?? '',
        );
        break;
      case 'onPaywallPurchaseStarted':
        d.onPaywallPurchaseStarted(
          args['paywallId'] as String? ?? '',
          args['productId'] as String? ?? '',
        );
        break;
      case 'onPaywallPurchaseCompleted':
        d.onPaywallPurchaseCompleted(
          args['paywallId'] as String? ?? '',
          args['productId'] as String? ?? '',
          (args['transaction'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      case 'onPaywallPurchaseFailed':
        d.onPaywallPurchaseFailed(
          args['paywallId'] as String? ?? '',
          // Generated delegate types this as `Object`; native sends either a
          // map ({ message, type }) or a raw string. Pass through verbatim.
          args['error'] ?? const <String, dynamic>{},
        );
        break;
      case 'onPaywallRestoreStarted':
        d.onPaywallRestoreStarted(args['paywallId'] as String? ?? '');
        break;
      case 'onPaywallRestoreCompleted':
        d.onPaywallRestoreCompleted(
          args['paywallId'] as String? ?? '',
          (args['restoredProductIds'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[],
        );
        break;
      case 'onPaywallRestoreFailed':
        d.onPaywallRestoreFailed(
          args['paywallId'] as String? ?? '',
          args['error'] ?? const <String, dynamic>{},
        );
        break;
      case 'onPaywallDismissed':
        d.onPaywallDismissed(args['paywallId'] as String? ?? '');
        break;
      default:
        break;
    }
  }
}

/// Remote config module namespace.
class AppDNARemoteConfigModule {
  final MethodChannel _channel;
  AppDNARemoteConfigModule._(this._channel);

  Future<dynamic> get(String key) =>
      _channel.invokeMethod('getRemoteConfig', {'key': key});
  Future<void> refresh() => _channel.invokeMethod('refreshConfig');

  /// Get all remote config values as a map.
  Future<Map<String, dynamic>> getAll() async {
    final data = await _channel.invokeMethod<Map>('getAllRemoteConfig');
    if (data != null) {
      return Map<String, dynamic>.from(data);
    }
    return {};
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
    final result =
        await _channel.invokeMethod<bool>('isFeatureEnabled', {'flag': flag});
    return result ?? false;
  }

  /// Get the variant value for a feature flag (for multi-variate flags).
  Future<dynamic> getVariant(String flag) async {
    return await _channel.invokeMethod('getFeatureVariant', {'flag': flag});
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
      _channel.invokeMethod<String>(
          'getExperimentVariant', {'experimentId': experimentId});
  Future<bool> isInVariant(String experimentId, String variantId) async {
    final result = await _channel.invokeMethod<bool>('isInVariant',
        {'experimentId': experimentId, 'variantId': variantId});
    return result ?? false;
  }

  /// Get all experiment exposures for the current user.
  Future<List<Map<String, dynamic>>> getExposures() async {
    final data = await _channel.invokeMethod<List>('getExperimentExposures');
    if (data != null) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}

/// In-app messages module namespace.
class AppDNAInAppMessagesModule {
  final MethodChannel _channel;
  AppDNAInAppMessageDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/in_app_message');

  AppDNAInAppMessagesModule._(this._channel);

  Future<void> suppressDisplay(bool suppress) =>
      _channel.invokeMethod('suppressMessages', {'suppress': suppress});

  /// Set a delegate to receive in-app message lifecycle callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNAInAppMessageDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onMessageShown':
        final messageId = args['messageId'] as String? ?? '';
        final trigger = args['trigger'] as String? ?? '';
        d.onMessageShown(messageId, trigger);
        // Non-breaking shim: 1.0.5 hosts that overrode onMessagePresented still fire.
        // ignore: deprecated_member_use_from_same_package
        d.onMessagePresented(messageId);
        break;
      case 'onMessageAction':
        d.onMessageAction(
          args['messageId'] as String? ?? '',
          args['action'] as String? ?? '',
        );
        break;
      case 'onMessageDismissed':
        d.onMessageDismissed(args['messageId'] as String? ?? '');
        break;
      case 'shouldShowMessage':
        d.shouldShowMessage(args['messageId'] as String? ?? '');
        break;
      default:
        break;
    }
  }
}

/// Surveys module namespace.
class AppDNASurveysModule {
  final MethodChannel _channel;
  AppDNASurveyDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/survey');

  AppDNASurveysModule._(this._channel);

  Future<void> present(String surveyId) =>
      _channel.invokeMethod('presentSurvey', {'surveyId': surveyId});

  /// Set a delegate to receive survey lifecycle callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNASurveyDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onSurveyPresented':
        d.onSurveyPresented(args['surveyId'] as String? ?? '');
        break;
      case 'onSurveyCompleted':
        final surveyId = args['surveyId'] as String? ?? '';
        final responses = (args['responses'] as List?)
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            <Map<String, dynamic>>[];
        d.onSurveyCompleted(surveyId, responses);
        // Non-breaking shim: 1.0.5 hosts that overrode onSurveySubmitted still fire
        // (with the first response, matching the old single-response shape).
        // ignore: deprecated_member_use_from_same_package
        d.onSurveySubmitted(
          surveyId,
          responses.isNotEmpty ? responses.first : <String, dynamic>{},
        );
        break;
      case 'onSurveyDismissed':
        d.onSurveyDismissed(args['surveyId'] as String? ?? '');
        break;
      default:
        break;
    }
  }
}

/// Deep links module namespace.
class AppDNADeepLinksModule {
  final MethodChannel _channel;
  AppDNADeepLinkDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/deep_link');

  AppDNADeepLinksModule._(this._channel);

  Future<void> handleURL(String url) =>
      _channel.invokeMethod('handleDeepLink', {'url': url});

  /// SPEC-070-C §3.13 — resolve a location the user picked for an onboarding
  /// location field. Returns `null` when the field has no captured location.
  Future<LocationData?> getLocationData(String fieldId) async {
    final data = await _channel
        .invokeMethod<Map>('getLocationData', {'fieldId': fieldId});
    if (data == null) return null;
    return LocationData.fromMap(data);
  }

  /// Set a delegate to receive deep link callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNADeepLinkDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onDeepLinkReceived':
        d.onDeepLinkReceived(
          args['url'] as String? ?? '',
          (args['params'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      case 'shouldOpen':
        d.shouldOpen(
          args['url'] as String? ?? '',
          (args['params'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      default:
        break;
    }
  }
}

/// Server-driven screen module namespace.
/// Forwards `com.appdna.sdk/events/screen` envelopes to an
/// `AppDNAScreenDelegate`.
class AppDNAScreenModule {
  final MethodChannel _channel;
  AppDNAScreenDelegate? _delegate;
  StreamSubscription? _eventSub;
  static const _events = EventChannel('com.appdna.sdk/events/screen');

  AppDNAScreenModule._(this._channel);

  /// Present a server-driven screen by ID. The screen is rendered natively;
  /// lifecycle callbacks fire on the registered [AppDNAScreenDelegate].
  Future<void> show(String screenId, {Map<String, dynamic>? context}) {
    return _channel.invokeMethod('showScreen', {
      'screenId': screenId,
      if (context != null) 'context': context,
    });
  }

  /// Present a multi-screen flow by ID. The flow runs through its configured
  /// screens; the delegate's `onFlowCompleted` fires when finished or abandoned.
  Future<void> showFlow(String flowId, {Map<String, dynamic>? context}) {
    return _channel.invokeMethod('showScreenFlow', {
      'flowId': flowId,
      if (context != null) 'context': context,
    });
  }

  /// Dismiss the currently-presented screen, if any.
  Future<void> dismiss() {
    return _channel.invokeMethod('dismissScreen');
  }

  /// Enable navigation interception so the delegate's `onScreenAction` is
  /// consulted before the SDK applies its default routing for nav actions.
  Future<void> enableNavigationInterception() {
    return _channel.invokeMethod('enableScreenNavigationInterception');
  }

  /// Disable navigation interception. The SDK resumes applying default
  /// routing for all nav actions.
  Future<void> disableNavigationInterception() {
    return _channel.invokeMethod('disableScreenNavigationInterception');
  }

  /// Render a screen from raw JSON for debugging or design preview.
  /// Use during development only.
  Future<void> preview(Map<String, dynamic> json) {
    return _channel.invokeMethod('previewScreen', {'json': json});
  }

  /// Set a delegate to receive server-driven screen lifecycle callbacks.
  /// Pass `null` to clear the current delegate and stop listening.
  void setDelegate(AppDNAScreenDelegate? delegate) {
    _delegate = delegate;
    _eventSub?.cancel();
    _eventSub = null;
    if (delegate == null) return;
    _eventSub = _events.receiveBroadcastStream().listen(_dispatch);
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type'] as String?;
    final args =
        (raw['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final d = _delegate;
    if (d == null || type == null) return;
    switch (type) {
      case 'onScreenPresented':
        d.onScreenPresented(args['screenId'] as String? ?? '');
        break;
      case 'onScreenDismissed':
        d.onScreenDismissed(
          args['screenId'] as String? ?? '',
          (args['result'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      case 'onFlowCompleted':
        d.onFlowCompleted(
          args['flowId'] as String? ?? '',
          (args['result'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      case 'onScreenAction':
        d.onScreenAction(
          args['screenId'] as String? ?? '',
          (args['action'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        );
        break;
      default:
        break;
    }
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
