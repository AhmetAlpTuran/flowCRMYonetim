import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../data/supabase_inbox_repository.dart';
import 'inbox_providers.dart';

typedef InboxSendScope = ({String tenantId, String conversationId});

class InboxSendState {
  const InboxSendState({this.busy = false, this.locked = false, this.error});
  final bool busy;
  final bool locked;
  final String? error;
}

class InboxSendController extends StateNotifier<InboxSendState> {
  InboxSendController(this.repository, this.scope)
      : super(const InboxSendState());
  final SupabaseInboxRepository repository;
  final InboxSendScope scope;
  String? _messageId;
  String? _body;
  bool _uncertain = false;

  Future<bool> send(String text) async {
    if (state.busy) return false;
    final body = _body ?? text.trim();
    if (body.isEmpty || body.runes.length > 4096) {
      state = const InboxSendState(
          error: 'Mesaj 1 ile 4096 karakter arasında olmalı.');
      return false;
    }
    _messageId ??= newRequestId();
    _body ??= body;
    state = const InboxSendState(busy: true, locked: true);
    try {
      await repository.queueMessage(
        tenantId: scope.tenantId,
        conversationId: scope.conversationId,
        messageId: _messageId!,
        body: _body!,
      );
      if (!mounted) return false;
      _messageId = null;
      _body = null;
      _uncertain = false;
      state = const InboxSendState();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _uncertain = _uncertain || error is! InboxSendFailure || error.uncertain;
      if (!_uncertain) {
        _messageId = null;
        _body = null;
      }
      state = InboxSendState(
        locked: _uncertain,
        error: _uncertain
            ? 'Gönderim isteği doğrulanamadı. Aynı mesajı kontrol etmek için tekrar deneyin.'
            : _errorMessage((error as InboxSendFailure).code),
      );
      return false;
    }
  }

  String _errorMessage(String code) => switch (code) {
        'customer_service_window_closed' =>
          '24 saatlik yanıt süresi doldu. Onaylı bir şablon kullanın.',
        'conversation_unmapped' =>
          'Bu eski konuşmanın WhatsApp hesabı henüz eşleştirilmedi.',
        'connection_unavailable' =>
          'WhatsApp bağlantısı kullanılamıyor. İşletme yöneticiniz bağlantıyı yenilemeli.',
        'unauthorized' => 'Oturumunuz sona erdi. Tekrar giriş yapın.',
        'forbidden' =>
          'Bu işletmenin gelen kutusunda mesaj gönderme yetkiniz yok.',
        'conversation_unavailable' =>
          'Konuşma kullanılamıyor. Gelen kutusunu yenileyin.',
        'invalid_message' => 'Mesaj 1 ile 4096 karakter arasında olmalı.',
        _ => 'Mesaj kaydedilemedi. Konuşmayı yenileyip tekrar deneyin.',
      };
}

final inboxSendProvider = StateNotifierProvider.autoDispose
    .family<InboxSendController, InboxSendState, InboxSendScope>((ref, scope) {
  return InboxSendController(ref.watch(inboxRepositoryProvider), scope);
});
