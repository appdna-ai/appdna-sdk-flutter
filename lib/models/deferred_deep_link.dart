/// A resolved deferred deep link.
class DeferredDeepLink {
  final String screen;
  final Map<String, String> params;
  final String visitorId;

  const DeferredDeepLink({
    required this.screen,
    required this.params,
    required this.visitorId,
  });

  factory DeferredDeepLink.fromMap(Map<String, dynamic> data) {
    return DeferredDeepLink(
      screen: data['screen'] as String? ?? '',
      params: Map<String, String>.from(data['params'] as Map? ?? {}),
      visitorId: data['visitorId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'screen': screen,
        'params': params,
        'visitorId': visitorId,
      };
}
