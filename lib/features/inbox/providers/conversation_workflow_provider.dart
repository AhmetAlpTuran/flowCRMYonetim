import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../data/supabase_inbox_repository.dart';
import '../models/conversation.dart';
import '../models/conversation_action.dart';
import 'inbox_providers.dart';

typedef ConversationScope = ({
  String tenantId,
  String conversationId,
  String userId
});

final conversationDetailProvider = FutureProvider.autoDispose
    .family<Conversation, ConversationScope>((ref, scope) {
  return ref.watch(inboxRepositoryProvider).fetchConversation(
      tenantId: scope.tenantId, conversationId: scope.conversationId);
});

final conversationTeamProvider = FutureProvider.autoDispose
    .family<List<ConversationTeamMember>, ConversationScope>((ref, scope) {
  return ref
      .watch(inboxRepositoryProvider)
      .fetchConversationTeam(scope.tenantId);
});

class ConversationWorkflowState {
  const ConversationWorkflowState(
      {this.busy = false, this.pending, this.error});
  final bool busy;
  final ConversationActionRequest? pending;
  final String? error;
}

class ConversationWorkflowController
    extends StateNotifier<ConversationWorkflowState> {
  ConversationWorkflowController(this.repository, this.scope)
      : super(const ConversationWorkflowState());
  final SupabaseInboxRepository repository;
  final ConversationScope scope;
  bool _uncertain = false;

  Future<bool> apply(ConversationAction action, int revision,
      {String? assigneeId}) async {
    if (state.busy) return false;
    final request = state.pending ??
        ConversationActionRequest(
            id: newRequestId(),
            revision: revision,
            action: action,
            assigneeId: assigneeId);
    state = ConversationWorkflowState(busy: true, pending: request);
    try {
      await repository.applyConversationAction(
          tenantId: scope.tenantId,
          conversationId: scope.conversationId,
          request: request);
      if (!mounted) return false;
      _uncertain = false;
      state = const ConversationWorkflowState();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _uncertain =
          _uncertain || error is! ConversationActionFailure || error.uncertain;
      state = ConversationWorkflowState(
          pending: _uncertain ? request : null,
          error: _uncertain
              ? 'İşlem sonucu doğrulanamadı. Aynı isteği tekrar kontrol edin.'
              : _errorMessage((error as ConversationActionFailure).code));
      return false;
    }
  }

  String _errorMessage(String code) => switch (code) {
        '40001' =>
          'Konuşma değişti. Güncel bilgileri inceleyip işlemi yeniden seçin.',
        '42501' =>
          'Bu konuşmada işlem yetkiniz değişti veya konuşma başka bir temsilciye atanmış.',
        '55000' => 'Bu işlem konuşmanın güncel durumunda kullanılamıyor.',
        'P0006' =>
          'Bekleyen yanıtlar var. Gönderimi bekleyin veya mesajı iptal edin.',
        'P0002' => 'Konuşma artık kullanılamıyor. Gelen kutusunu yenileyin.',
        '22023' =>
          'Seçilen temsilci kullanılamıyor. Ekibi yenileyip yeniden seçin.',
        _ => 'İşlem kaydedilemedi. Konuşmayı yenileyin.',
      };
}

final conversationWorkflowProvider = StateNotifierProvider.autoDispose.family<
    ConversationWorkflowController,
    ConversationWorkflowState,
    ConversationScope>((ref, scope) {
  return ConversationWorkflowController(
      ref.watch(inboxRepositoryProvider), scope);
});
