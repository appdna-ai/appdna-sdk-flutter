/// Log verbosity levels.
enum AppDNALogLevel { none, error, warning, info, debug }

/// Billing provider for paywall purchases (iOS only).
enum AppDNABillingProvider { storeKit2, revenueCat, none }

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

  AppDNAOptions({
    this.flushInterval,
    this.batchSize,
    this.configTTL,
    this.logLevel,
    this.billingProvider,
  });

  Map<String, dynamic> toMap() => {
        if (flushInterval != null) 'flushInterval': flushInterval,
        if (batchSize != null) 'batchSize': batchSize,
        if (configTTL != null) 'configTTL': configTTL,
        if (logLevel != null) 'logLevel': logLevel!.name,
        if (billingProvider != null) 'billingProvider': billingProvider!.name,
      };
}
