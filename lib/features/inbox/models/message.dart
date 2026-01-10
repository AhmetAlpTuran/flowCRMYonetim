enum MessageStatus {
  sent,
  delivered,
  read,
  failed,
  unknown,
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.sentAt,
    required this.isFromCustomer,
    this.status = MessageStatus.unknown,
    this.waMessageId,
    this.deliveredAt,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String sender;
  final String text;
  final DateTime sentAt;
  final bool isFromCustomer;
  final MessageStatus status;
  final String? waMessageId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
}
