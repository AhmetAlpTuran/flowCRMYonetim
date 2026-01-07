import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation.dart';
import '../models/message.dart';

class SupabaseInboxRepository {
  SupabaseInboxRepository(this._client);

  final SupabaseClient _client;

  Future<List<Conversation>> fetchConversations({required String tenantId}) async {
    final response = await _client
        .from('conversations')
        .select()
        .eq('tenant_id', tenantId)
        .order('updated_at', ascending: false);
    return response.map<Conversation>(_fromConversation).toList();
  }

  Future<List<Message>> fetchMessages(String conversationId) async {
    final response = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: true);
    return response.map<Message>(_fromMessage).toList();
  }

  Future<List<Conversation>> updateTags({
    required String tenantId,
    required String conversationId,
    required List<String> tags,
  }) async {
    await _client
        .from('conversations')
        .update({'tags': tags}).eq('id', conversationId);
    return fetchConversations(tenantId: tenantId);
  }

  Conversation _fromConversation(Map<String, dynamic> row) {
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      lastMessage: row['last_message'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
      unreadCount: (row['unread_count'] as int?) ?? 0,
      status: _statusFromString(row['status'] as String),
      tags: List<String>.from(row['tags'] as List<dynamic>? ?? const []),
    );
  }

  Message _fromMessage(Map<String, dynamic> row) {
    return Message(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      sender: row['sender'] as String,
      text: row['body'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String),
      isFromCustomer: row['is_from_customer'] as bool? ?? false,
    );
  }

  ConversationStatus _statusFromString(String value) {
    switch (value) {
      case 'open':
        return ConversationStatus.open;
      case 'pending':
        return ConversationStatus.pending;
      case 'handoff':
        return ConversationStatus.handoff;
      case 'closed':
        return ConversationStatus.closed;
      default:
        return ConversationStatus.open;
    }
  }
}