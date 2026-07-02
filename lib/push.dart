import 'dart:async';
import 'package:flutter/services.dart';
import 'models/push_payload.dart';

export 'models/push_payload.dart';

/// Push notification management for AppDNA Flutter SDK.
class AppDNAPush {
  static const MethodChannel _channel = MethodChannel('com.appdna.sdk/main');
  static const EventChannel _pushReceivedChannel =
      EventChannel('com.appdna.sdk/push_received');
  static const EventChannel _pushTappedChannel =
      EventChannel('com.appdna.sdk/push_tapped');

  /// Request push notification permission.
  static Future<bool> requestPermission() async {
    final result = await _channel.invokeMethod<bool>('requestPushPermission');
    return result ?? false;
  }

  /// SPEC-070-C §3.11 — request permission AND register for remote
  /// notifications. Returns whether permission was granted. Real on iOS;
  /// on Android this routes to [requestPermission] (§3.14).
  static Future<bool> registerForPush() async {
    final result = await _channel.invokeMethod<bool>('registerForPush');
    return result ?? false;
  }

  /// SPEC-070-C §3.11 — hand a push-open (notification tap) to the SDK so it
  /// can attribute + route the tap using the current activity's launch intent.
  /// Returns whether the SDK handled it. **Android-only** — a no-op returning
  /// `false` on iOS (§3.14).
  static Future<bool> handlePushTap() async {
    final result = await _channel.invokeMethod<bool>('handlePushTap');
    return result ?? false;
  }

  /// SPEC-070-C §3.11 — feed a freshly-issued push token (e.g. from FCM
  /// `onNewToken`) into the SDK for backend registration. **Android-only** — a
  /// no-op on iOS (§3.14).
  static Future<void> onNewPushToken(String token) async {
    await _channel.invokeMethod('onNewPushToken', {'token': token});
  }

  /// Stream of received push notifications.
  static Stream<PushPayload> get onPushReceived {
    return _pushReceivedChannel.receiveBroadcastStream().map((data) {
      return PushPayload.fromMap(Map<String, dynamic>.from(data as Map));
    });
  }

  /// Stream of tapped push notifications.
  static Stream<PushPayload> get onPushTapped {
    return _pushTappedChannel.receiveBroadcastStream().map((data) {
      return PushPayload.fromMap(Map<String, dynamic>.from(data as Map));
    });
  }
}
