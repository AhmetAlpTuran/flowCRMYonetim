enum ConversationStatus {
  open,
  pending,
  handoff,
  closed,
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.updatedAt,
    required this.unreadCount,
    required this.status,
    required this.tags,
  });

  final String id;
  final String title;
  final String lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final ConversationStatus status;
  final List<String> tags;

  Conversation copyWith({
    String? title,
    String? lastMessage,
    DateTime? updatedAt,
    int? unreadCount,
    ConversationStatus? status,
    List<String>? tags,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      status: status ?? this.status,
      tags: tags ?? this.tags,
    );
  }
}