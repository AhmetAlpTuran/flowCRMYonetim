import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/conversation_action.dart';
import '../../handoff/models/handoff_request.dart';

class InboxSendFailure implements Exception {
  const InboxSendFailure(this.code, {required this.uncertain});
  final String code;
  final bool uncertain;
}

class SupabaseInboxRepository {
  SupabaseInboxRepository(this._client);

  final SupabaseClient _client;

  Future<List<HandoffRequest>> fetchHandoffRequests({
    required String tenantId,
    required int page,
    String? status,
  }) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    var query = _client
        .from('handoff_requests')
        .select('id, conversation_id, status, note, created_at, created_by, '
            'conversation:conversations!handoff_conversation_tenant_fk(title)')
        .eq('tenant_id', tenantId);
    if (status != null) query = query.eq('status', status);
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(page * handoffPageSize, (page + 1) * handoffPageSize)
        .timeout(const Duration(seconds: 20));
    return rows
        .map((row) => HandoffRequest(
              id: row['id'] as String,
              conversationId: row['conversation_id'] as String,
              title: (row['conversation'] as Map<String, dynamic>?)?['title']
                      as String? ??
                  'Konuşma',
              status: row['status'] as String? ?? 'open',
              createdAt: DateTime.parse(row['created_at'] as String),
              note: row['note'] as String?,
              createdBy: row['created_by'] as String?,
            ))
        .toList();
  }

  Future<Conversation> fetchConversation({
    required String tenantId,
    required String conversationId,
  }) async {
    final row = await _client
        .from('conversations')
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', conversationId)
        .single()
        .timeout(const Duration(seconds: 20));
    return _fromConversation(row);
  }

  Future<List<ConversationTeamMember>> fetchConversationTeam(
      String tenantId) async {
    final response = await _client.rpc('conversation_team', params: {
      'p_tenant_id': tenantId,
    }).timeout(const Duration(seconds: 20));
    return (response as List)
        .map((row) => ConversationTeamMember(
              id: row['user_id'] as String,
              name: row['display_name'] as String,
            ))
        .toList();
  }

  Future<void> applyConversationAction({
    required String tenantId,
    required String conversationId,
    required ConversationActionRequest request,
  }) async {
    try {
      final result = await _client.rpc('apply_conversation_action', params: {
        'p_tenant_id': tenantId,
        'p_conversation_id': conversationId,
        'p_request_id': request.id,
        'p_expected_revision': request.revision,
        'p_action': request.action.name,
        'p_assignee_id': request.assigneeId,
      }).timeout(const Duration(seconds: 20));
      if (result is! Map ||
          result['conversation_id'] != conversationId ||
          result['workflow_revision'] is! num) {
        throw const ConversationActionFailure('unconfirmed', uncertain: true);
      }
    } on PostgrestException catch (error) {
      throw ConversationActionFailure(error.code ?? 'unconfirmed',
          uncertain: !const {
            '42501',
            '40001',
            '22023',
            '55000',
            'P0002',
            'P0006'
          }.contains(error.code));
    }
  }

  Future<void> cancelMessage({
    required String tenantId,
    required String conversationId,
    required String messageId,
  }) async {
    final result = await _client.rpc('cancel_inbox_message', params: {
      'p_tenant_id': tenantId,
      'p_conversation_id': conversationId,
      'p_message_id': messageId,
    }).timeout(const Duration(seconds: 20));
    if (result != true) {
      throw const ConversationActionFailure('unconfirmed', uncertain: true);
    }
  }

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
        .select('*, media:message_media(kind, state, storage_path, mime_type, '
            'file_name, caption, size_bytes)')
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
        'conversation_closed',
        'conversation_assigned_elsewhere',
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
      assignedTo: row['assigned_to'] as String?,
      workflowRevision: (row['workflow_revision'] as num?)?.toInt() ?? 0,
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
      sentBy: row['sent_by'] as String?,
      media: MessageMedia.fromEmbedded(row['media']),
    );
  }

  /// Short-lived link to a stored media file (Storage RLS checks inbox access).
  Future<String> mediaUrl(String storagePath) => _client.storage
      .from('inbox-media')
      .createSignedUrl(storagePath, 3600)
      .timeout(const Duration(seconds: 20));

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
