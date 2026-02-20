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
