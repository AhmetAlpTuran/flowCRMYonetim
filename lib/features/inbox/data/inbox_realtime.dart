import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live change feeds for the inbox. Each `watch*` call opens one Supabase realtime
/// channel and returns the function that closes it. Widget tests override
/// `inboxRealtimeProvider` with [InboxRealtime.silent], which opens nothing.
class InboxRealtime {
  const InboxRealtime();

  /// A feed that never connects (tests, previews).
  const factory InboxRealtime.silent() = _SilentInboxRealtime;

  /// Calls [onChange] whenever a conversation of [tenantId] changes.
  VoidCallback watchConversations(String tenantId, VoidCallback onChange) {
    final channel = Supabase.instance.client
        .channel('conversations:$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => channel.unsubscribe();
  }

  /// Calls [onMessages] when a message of the conversation changes and [onMedia]
  /// when a media download finishes (that only changes `message_media`).
  VoidCallback watchMessages(
    String conversationId, {
    required VoidCallback onMessages,
    required VoidCallback onMedia,
  }) {
    final channel = Supabase.instance.client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => onMessages(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'message_media',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => onMedia(),
        )
        .subscribe();
    return () => channel.unsubscribe();
  }
}

class _SilentInboxRealtime extends InboxRealtime {
  const _SilentInboxRealtime();

  @override
  VoidCallback watchConversations(String tenantId, VoidCallback onChange) => () {};

  @override
  VoidCallback watchMessages(
    String conversationId, {
    required VoidCallback onMessages,
    required VoidCallback onMedia,
  }) =>
      () {};
}
