import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../data/supabase_inbox_repository.dart';
import '../models/outbound_media.dart';
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
  OutboundMediaFile? _media;
  String? _mediaPath;
  bool _uncertain = false;

  /// True while a file is waiting to be sent or re-checked.
  bool get hasPendingMedia => _media != null;

  /// Sends a photo or document with an optional caption. The same message ID,
  /// file and caption are reused until the result is confirmed.
  Future<bool> sendMedia(OutboundMediaFile file, {String caption = ''}) async {
    if (state.busy) return false;
    if (_media == null) {
      if (_uncertain) return false;
      final text = caption.trim();
      if (text.runes.length > 1024) {
        state = const InboxSendState(error: 'Açıklama en fazla 1024 karakter olabilir.');
        return false;
      }
      _messageId = newRequestId();
      _media = file;
      _body = text;
      _mediaPath = null;
    }
    return _sendPendingMedia();
  }

  /// Drops a file that failed definitively (never one with an uncertain result).
  void discardMedia() {
    if (_uncertain || state.busy) return;
    _reset();
    state = const InboxSendState();
  }

  void _reset() {
    _messageId = null;
    _body = null;
    _media = null;
    _mediaPath = null;
    _uncertain = false;
  }

  Future<bool> _sendPendingMedia() async {
    state = const InboxSendState(busy: true, locked: true);
    try {
      _mediaPath ??= await repository.uploadOutboundMedia(
        tenantId: scope.tenantId,
        conversationId: scope.conversationId,
        messageId: _messageId!,
        file: _media!,
      );
      await repository.queueMessage(
        tenantId: scope.tenantId,
        conversationId: scope.conversationId,
        messageId: _messageId!,
        body: _body!,
        media: _media,
        mediaPath: _mediaPath,
      );
      if (!mounted) return false;
      _reset();
      state = const InboxSendState();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _uncertain = _uncertain || error is! InboxSendFailure || error.uncertain;
      final code = error is InboxSendFailure ? error.code : '';
      state = InboxSendState(
        // Keep the file so the same send can be retried or discarded.
        locked: true,
        error: _uncertain
            ? 'Dosya gönderimi doğrulanamadı. Aynı dosyayı kontrol etmek için tekrar deneyin.'
            : code == 'media_upload_failed'
                ? 'Dosya yüklenemedi. Tekrar deneyin veya dosyayı kaldırın.'
                : _errorMessage(code),
      );
      return false;
    }
  }

  Future<bool> send(String text) async {
    if (state.busy) return false;
    if (_media != null) return _sendPendingMedia();
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
        'conversation_closed' => 'Yanıtlamak için önce konuşmayı yeniden açın.',
        'conversation_assigned_elsewhere' =>
          'Konuşma başka bir temsilciye atanmış. Yanıtlamak için yöneticinizden size atamasını isteyin.',
        'invalid_message' => 'Mesaj 1 ile 4096 karakter arasında olmalı.',
        'invalid_media' =>
          'Dosya gönderilemedi: JPG/PNG fotoğraf en fazla 5 MB, belge en fazla 16 MB olmalı.',
        _ => 'Mesaj kaydedilemedi. Konuşmayı yenileyip tekrar deneyin.',
      };
}

final inboxSendProvider = StateNotifierProvider.autoDispose
    .family<InboxSendController, InboxSendState, InboxSendScope>((ref, scope) {
  return InboxSendController(ref.watch(inboxRepositoryProvider), scope);
});
