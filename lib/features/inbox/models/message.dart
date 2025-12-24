class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.text,
    required this.sentAt,
    required this.isFromCustomer,
  });

  final String id;
  final String conversationId;
  final String sender;
  final String text;
  final DateTime sentAt;
  final bool isFromCustomer;
}