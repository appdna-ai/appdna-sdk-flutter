class PushPayload {
  final String pushId;
  final String title;
  final String body;
  final String? imageUrl;
  final Map<String, dynamic>? data;
  final String? actionType;
  final String? actionValue;

  PushPayload({
    required this.pushId,
    required this.title,
    required this.body,
    this.imageUrl,
    this.data,
    this.actionType,
    this.actionValue,
  });

  factory PushPayload.fromMap(Map<String, dynamic> map) {
    return PushPayload(
      pushId: map['push_id'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      imageUrl: map['image_url'],
      data: map['data'] as Map<String, dynamic>?,
      actionType: map['action_type'],
      actionValue: map['action_value'],
    );
  }
}
