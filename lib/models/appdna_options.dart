/// Log verbosity levels.
enum AppDNALogLevel { none, error, warning, info, debug }

/// Billing provider for paywall purchases (iOS only).
///
/// Value-less providers cross the channel as a bare string; `adapty` carries an
/// API key and crosses as a tagged map `{"type":"adapty","apiKey":"…"}` — mirroring
/// the native `BillingProvider.adapty(apiKey:)` associated-value case (SPEC-070-C §3.1).
class AppDNABillingProvider {
  /// Provider discriminator: `storeKit2` | `revenueCat` | `adapty` | `none`.
  final String type;

  /// Adapty public SDK key (only set for the `adapty` provider).
  final String? apiKey;

  const AppDNABillingProvider._(this.type, {this.apiKey});

  static const AppDNABillingProvider storeKit2 =
      AppDNABillingProvider._('storeKit2');
  static const AppDNABillingProvider revenueCat =
      AppDNABillingProvider._('revenueCat');
  static const AppDNABillingProvider none = AppDNABillingProvider._('none');

  /// Adapty billing, keyed by your Adapty public SDK key.
  factory AppDNABillingProvider.adapty(String apiKey) =>
      AppDNABillingProvider._('adapty', apiKey: apiKey);

  /// Channel encoding: a bare string for value-less cases, a tagged map for adapty.
  Object toJson() => apiKey == null
      ? type
      : <String, dynamic>{'type': type, 'apiKey': apiKey};
}

/// Configuration options for the AppDNA SDK.
class AppDNAOptions {
  /// Automatic flush interval in seconds. Default: 30.
  final int? flushInterval;

  /// Number of events per flush batch. Default: 20.
  final int? batchSize;

  /// Remote config cache TTL in seconds. Default: 300 (5 min).
  final int? configTTL;

  /// Log verbosity. Default: warning.
  final AppDNALogLevel? logLevel;

  /// Billing provider for paywall purchases (iOS only). Default: storeKit2.
  final AppDNABillingProvider? billingProvider;

  /// Notification small-icon drawable resource id used for AppDNA push
  /// notifications (**Android only**; iOS ignores it — §3.14). `0`/unset falls
  /// back to manifest meta-data then the app icon.
  ///
  /// Caveat: this is an Android `R.drawable.*` resource id (an `int`) — a
  /// pure-Dart host has no such id, so it is only useful when a native Android
  /// layer supplies it. Bridged for full §3.1 surface parity.
  final int? notificationIcon;

  /// SPEC-070-C D4 — SDK-wrapper attribution tagged on every event's device
  /// context (→ BigQuery `framework` column). The Flutter SDK always reports
  /// `flutter`; this override exists only for special embedding scenarios.
  final String? framework;

  const AppDNAOptions({
    this.flushInterval,
    this.batchSize,
    this.configTTL,
    this.logLevel,
    this.billingProvider,
    this.notificationIcon,
    this.framework,
  });

  Map<String, dynamic> toMap() => {
        if (flushInterval != null) 'flushInterval': flushInterval,
        if (batchSize != null) 'batchSize': batchSize,
        if (configTTL != null) 'configTTL': configTTL,
        if (logLevel != null) 'logLevel': logLevel!.name,
        if (billingProvider != null) 'billingProvider': billingProvider!.toJson(),
        if (notificationIcon != null) 'notificationIcon': notificationIcon,
        // Always tag Flutter traffic (defaults to 'flutter' when not overridden).
        'framework': framework ?? 'flutter',
      };
}
