import 'dart:async';
import 'package:flutter/services.dart';

/// Represents a user's entitlement to a product or subscription.
class Entitlement {
  final String productId;
  final String store;
  final String status;
  final String? expiresAt;
  final bool isTrial;
  final String? offerType;

  Entitlement({
    required this.productId,
    required this.store,
    required this.status,
    this.expiresAt,
    this.isTrial = false,
    this.offerType,
  });

  factory Entitlement.fromMap(Map<dynamic, dynamic> map) {
    return Entitlement(
      productId: map['productId'] ?? '',
      store: map['store'] ?? '',
      status: map['status'] ?? '',
      expiresAt: map['expiresAt'],
      isTrial: map['isTrial'] ?? false,
      offerType: map['offerType'],
    );
  }
}

/// Result of a purchase operation.
class PurchaseResult {
  /// Status of the purchase: purchased, cancelled, pending, or unknown.
  final String status;

  /// The entitlement granted by the purchase, if successful.
  final Entitlement? entitlement;

  PurchaseResult({required this.status, this.entitlement});

  factory PurchaseResult.fromMap(Map<dynamic, dynamic> map) {
    return PurchaseResult(
      status: map['status'] ?? 'unknown',
      entitlement: map['entitlement'] != null
          ? Entitlement.fromMap(map['entitlement'])
          : null,
    );
  }
}

/// Localized product information from the app store.
class ProductInfo {
  final String id;
  final String name;
  final String description;
  final String displayPrice;
  final double price;
  final String? offerToken;

  ProductInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.displayPrice,
    required this.price,
    this.offerToken,
  });

  factory ProductInfo.fromMap(Map<dynamic, dynamic> map) {
    return ProductInfo(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      displayPrice: map['displayPrice'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      offerToken: map['offerToken'],
    );
  }
}

/// Billing bridge for AppDNA in-app purchases.
///
/// Provides purchase, restore, product info, and entitlement streaming
/// via platform channels that delegate to native iOS/Android SDKs.
class AppDNABilling {
  static const MethodChannel _channel =
      MethodChannel('com.appdna.sdk/billing');
  static const EventChannel _entitlementChannel =
      EventChannel('com.appdna.sdk/entitlements');

  /// Set a delegate to receive billing lifecycle callbacks (purchases, failures, restores).
  static void setDelegate(dynamic delegate) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPurchaseCompleted':
          delegate.onPurchaseCompleted(call.arguments['productId']);
          break;
        case 'onPurchaseFailed':
          delegate.onPurchaseFailed(
              call.arguments['productId'], call.arguments['error']);
          break;
        case 'onEntitlementsChanged':
          final List<Map<String, dynamic>> entitlements =
              (call.arguments['entitlements'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          delegate.onEntitlementsChanged(entitlements);
          break;
        case 'onRestoreCompleted':
          final List<Map<String, dynamic>> entitlements =
              (call.arguments['entitlements'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          delegate.onRestoreCompleted(entitlements);
          break;
      }
    });
  }

  /// Purchase a product by its store product ID.
  ///
  /// On Android, pass [offerToken] for subscription offers (base plan tokens).
  /// Returns a [PurchaseResult] indicating the outcome.
  static Future<PurchaseResult> purchase(String productId,
      {String? offerToken}) async {
    final result = await _channel.invokeMethod('purchase', {
      'productId': productId,
      'offerToken': offerToken,
    });
    return PurchaseResult.fromMap(Map<dynamic, dynamic>.from(result));
  }

  /// Restore previously purchased products.
  ///
  /// Syncs with the App Store / Google Play and returns all active entitlements.
  static Future<List<Entitlement>> restorePurchases() async {
    final result = await _channel.invokeMethod('restorePurchases');
    return (result as List)
        .map((e) => Entitlement.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList();
  }

  /// Get localized product information from the store.
  ///
  /// Pass a list of product IDs configured in App Store Connect / Google Play Console.
  static Future<List<ProductInfo>> getProducts(List<String> productIds) async {
    final result =
        await _channel.invokeMethod('getProducts', {'productIds': productIds});
    return (result as List)
        .map((e) => ProductInfo.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList();
  }

  /// Check if the user has an active subscription.
  static Future<bool> get hasActiveSubscription async {
    return await _channel.invokeMethod('hasActiveSubscription');
  }

  /// Get all current entitlements for the user.
  static Future<List<Entitlement>> getEntitlements() async {
    final result = await _channel.invokeMethod('getEntitlements');
    return (result as List)
        .map((e) => Entitlement.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList();
  }

  /// Stream of entitlement changes.
  ///
  /// Emits updated entitlements when purchases, renewals, or revocations occur.
  static Stream<List<Entitlement>> get onEntitlementsChanged {
    return _entitlementChannel
        .receiveBroadcastStream()
        .map((data) => (data as List)
            .map((e) => Entitlement.fromMap(Map<dynamic, dynamic>.from(e)))
            .toList());
  }
}
