class HandoffRequest {
  const HandoffRequest({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.note,
    this.createdBy,
  });

  final String id;
  final String conversationId;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? note;
  final String? createdBy;
}
