/// Additional context for paywall presentation.
class PaywallContext {
  final String? placement;
  final Map<String, dynamic>? customData;

  const PaywallContext({this.placement, this.customData});

  Map<String, dynamic> toMap() => {
        if (placement != null) 'placement': placement,
        if (customData != null) 'customData': customData,
      };
}
