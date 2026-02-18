/// Represents a web subscription entitlement from Stripe web checkout.
class WebEntitlement {
  final bool isActive;
  final String? planName;
  final String? priceId;
  final String? interval;
  final String status;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEnd;

  const WebEntitlement({
    required this.isActive,
    this.planName,
    this.priceId,
    this.interval,
    required this.status,
    this.currentPeriodEnd,
    this.trialEnd,
  });

  factory WebEntitlement.fromMap(Map<String, dynamic> data) {
    return WebEntitlement(
      isActive: data['isActive'] as bool? ?? false,
      planName: data['planName'] as String?,
      priceId: data['priceId'] as String?,
      interval: data['interval'] as String?,
      status: data['status'] as String? ?? 'canceled',
      currentPeriodEnd: data['currentPeriodEnd'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['currentPeriodEnd'] as num).toInt() * 1000)
          : null,
      trialEnd: data['trialEnd'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (data['trialEnd'] as num).toInt() * 1000)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'isActive': isActive,
        'planName': planName,
        'priceId': priceId,
        'interval': interval,
        'status': status,
        'currentPeriodEnd':
            currentPeriodEnd?.millisecondsSinceEpoch,
        'trialEnd': trialEnd?.millisecondsSinceEpoch,
      };
}
