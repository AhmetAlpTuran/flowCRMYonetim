import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation.dart';
import '../models/message.dart';

class InboxSendFailure implements Exception {
  const InboxSendFailure(this.code, {required this.uncertain});
  final String code;
  final bool uncertain;
}

class SupabaseInboxRepository {
  SupabaseInboxRepository(this._client);

  final SupabaseClient _client;

  Future<List<Conversation>> fetchConversations(
      {required String tenantId}) async {
    final response = await _client
        .from('conversations')
        .select()
        .eq('tenant_id', tenantId)
        .order('updated_at', ascending: false);
    return response.map<Conversation>(_fromConversation).toList();
  }

  Future<List<Message>> fetchMessages(String conversationId,
      {required String tenantId}) async {
    final response = await _client
        .from('messages')
        .select()
        .eq('tenant_id', tenantId)
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
        .update({'tags': tags})
        .eq('tenant_id', tenantId)
        .eq('id', conversationId);
    return fetchConversations(tenantId: tenantId);
  }

  Future<void> markOpened({
    required String tenantId,
    required String conversationId,
  }) async {
    await _client.rpc('mark_conversation_opened', params: {
      'p_tenant_id': tenantId,
      'p_conversation_id': conversationId,
    }).timeout(const Duration(seconds: 20));
  }

  Future<void> queueMessage({
    required String tenantId,
    required String conversationId,
    required String messageId,
    required String body,
  }) async {
    try {
      final response = await _client.functions.invoke('send-message', body: {
        'tenant_id': tenantId,
        'conversation_id': conversationId,
        'message_id': messageId,
        'body': body,
      }).timeout(const Duration(seconds: 20));
      final data = response.data;
      if (response.status != 202 ||
          data is! Map ||
          data['message_id'] != messageId ||
          !const {
            'queued',
            'leased',
            'sending',
            'retry_wait',
            'blocked',
            'accepted',
            'failed',
            'unknown',
            'cancelled',
          }.contains(data['state'])) {
        throw const InboxSendFailure('enqueue_unconfirmed', uncertain: true);
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map && details['code'] is String
          ? details['code'] as String
          : 'enqueue_unconfirmed';
      const definitive = {
        'forbidden',
        'unauthorized',
        'conversation_unavailable',
        'conversation_unmapped',
        'customer_service_window_closed',
        'connection_unavailable',
        'message_identity_conflict',
        'invalid_message',
      };
      throw InboxSendFailure(code,
          uncertain: error.status >= 500 || !definitive.contains(code));
    }
  }

  Future<void> requestHandoff({
    required String tenantId,
    required String conversationId,
    required String requestId,
    required String note,
  }) async {
    await _client.rpc('request_conversation_handoff', params: {
      'p_tenant_id': tenantId,
      'p_conversation_id': conversationId,
      'p_request_id': requestId,
      'p_note': note,
    }).timeout(const Duration(seconds: 20));
  }

  Conversation _fromConversation(Map<String, dynamic> row) {
    final lastOpened = row['last_opened_at'] as String?;
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      lastMessage: row['last_message'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
      unreadCount: (row['unread_count'] as int?) ?? 0,
      status: _statusFromString(row['status'] as String),
      tags: List<String>.from(row['tags'] as List<dynamic>? ?? const []),
      lastOpenedAt: lastOpened == null ? null : DateTime.parse(lastOpened),
      lastOpenedBy: row['last_opened_by'] as String?,
      lastOpenedRole: row['last_opened_role'] as String?,
    );
  }

  Message _fromMessage(Map<String, dynamic> row) {
    final deliveredAt = row['delivered_at'] as String?;
    final readAt = row['read_at'] as String?;
    return Message(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      sender: row['sender'] as String,
      text: row['body'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String),
      isFromCustomer: row['is_from_customer'] as bool? ?? false,
      status: _messageStatusFromString(row['wa_status'] as String?),
      waMessageId: row['wa_message_id'] as String?,
      deliveredAt: deliveredAt == null ? null : DateTime.parse(deliveredAt),
      readAt: readAt == null ? null : DateTime.parse(readAt),
      outboundState: row['outbound_state'] as String?,
      outboundErrorCode: row['outbound_error_code'] as String?,
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

  MessageStatus _messageStatusFromString(String? value) {
    switch (value) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return MessageStatus.unknown;
    }
  }
}
