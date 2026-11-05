import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../handoff/providers/handoff_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/conversation.dart';
import '../models/conversation_action.dart';
import '../providers/conversation_workflow_provider.dart';
import '../providers/inbox_providers.dart';
import 'conversation_badge.dart';

Future<bool?> showConversationWorkflow(
    BuildContext context, ConversationScope scope) {
  return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ConversationWorkflowSheet(scope: scope));
}

/// Ownership and case actions for one conversation, shared by the chat and the
/// handoff list. The controller keeps one immutable request for uncertain retries.
class ConversationWorkflowSheet extends ConsumerStatefulWidget {
  const ConversationWorkflowSheet({super.key, required this.scope});
  final ConversationScope scope;

  @override
  ConsumerState<ConversationWorkflowSheet> createState() =>
      _ConversationWorkflowSheetState();
}

class _ConversationWorkflowSheetState
    extends ConsumerState<ConversationWorkflowSheet> {
  String? _assigneeId;
  bool _invalidated = false;
  bool _allowClose = false;
  bool _closing = false;

  bool get _currentScope =>
      ref.read(selectedTenantProvider)?.id == widget.scope.tenantId &&
      ref.read(authControllerProvider).valueOrNull?.userId ==
          widget.scope.userId;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(selectedTenantProvider)?.id != widget.scope.tenantId ||
        ref.watch(authControllerProvider).valueOrNull?.userId !=
            widget.scope.userId) {
      _invalidated = true;
    }
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(conversationWorkflowProvider(widget.scope));
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final canAct =
        !_invalidated && (membership?.hasPermission('inbox') ?? false);
    return PopScope<bool>(
      canPop: _allowClose || (!state.busy && state.pending == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
          child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: SingleChildScrollView(
            child: Padding(
          padding: EdgeInsets.fromLTRB(FlowSpace.xl - 4, FlowSpace.xl - 4,
              FlowSpace.xl - 4, FlowSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Konuşmayı yönet', style: theme.textTheme.titleLarge),
                const SizedBox(height: FlowSpace.lg),
                if (!canAct)
                  const InboxNotice(
                      'Oturum, işletme veya yetkiniz değişti. Bu pencereyi kapatıp gelen kutusuna dönün.')
                else
                  ref.watch(conversationDetailProvider(widget.scope)).when(
                        skipLoadingOnRefresh: false,
                        data: (conversation) =>
                            _actions(conversation, membership!.isAdmin, state),
                        error: (_, __) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const InboxNotice(
                                  'Konuşma yüklenemedi. Erişiminizi kontrol edip tekrar deneyin.'),
                              const SizedBox(height: FlowSpace.sm),
                              OutlinedButton.icon(
                                  onPressed: state.busy ? null : _refresh,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Yenile')),
                            ]),
                        loading: () => const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator())),
                      ),
                if (state.error != null) ...[
                  const SizedBox(height: FlowSpace.md),
                  InboxNotice(state.error!,
                      tone: state.pending != null
                          ? FlowTone.warning
                          : FlowTone.danger),
                ],
                if (canAct && state.pending != null) ...[
                  const SizedBox(height: FlowSpace.md),
                  Text(upperTr('Bekleyen işlem · ${state.pending!.action.label}'),
                      style: FlowText.caps(context, color: c.warning)),
                  const SizedBox(height: FlowSpace.sm),
                  FilledButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => _apply(
                              state.pending!.action, state.pending!.revision,
                              assigneeId: state.pending!.assigneeId),
                      icon: state.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 18),
                      label: const Text('Aynı isteği kontrol et')),
                ],
                const SizedBox(height: FlowSpace.md),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: state.busy ? null : _close,
                        style: TextButton.styleFrom(foregroundColor: c.muted),
                        child: const Text('Kapat'))),
              ]),
        )),
      )),
    );
  }

  Widget _actions(
      Conversation conversation, bool admin, ConversationWorkflowState state) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final mine = conversation.assignedTo == widget.scope.userId;
    final available = conversation.assignedTo == null || mine || admin;
    final closed = conversation.status == ConversationStatus.closed;
    final disabled = state.busy || state.pending != null;
    final team = ref.watch(conversationTeamProvider(widget.scope));
    final members = team.valueOrNull ?? const <ConversationTeamMember>[];
    final owners =
        members.where((member) => member.id == conversation.assignedTo);
    final owner = conversation.assignedTo == null
        ? 'Atanmamış'
        : mine
            ? 'Siz'
            : owners.isEmpty
                ? 'Başka bir temsilci'
                : owners.first.name;
    final selected =
        members.any((member) => member.id == _assigneeId) ? _assigneeId : null;
    // One lime button per view: the retry owns it while a request is pending.
    final claimPrimary = state.pending == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(FlowSpace.md + 2),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: FlowRadius.cardAll,
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            InitialsAvatar(conversation.title, size: 36),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Text(conversation.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: FlowSpace.md),
          Row(children: [
            Expanded(
                child: Text('Durum',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted))),
            ConversationStatusBadge(
                conversation: conversation, userId: widget.scope.userId),
          ]),
          KeyValueRow(label: 'Atanan', value: owner),
        ]),
      ),
      const SizedBox(height: FlowSpace.md),
      Text(
          'Üstlenilen konuşmalar insan kontrolünde kalır. Çözüm, mevcut destek kaydını kapatır. Yeni bir müşteri mesajı yeni kayıt açabilir.',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: FlowSpace.lg),
      if (!available)
        const InboxNotice(
            'Konuşma başka bir temsilcide. Atamayı değiştirmek için yöneticinize başvurun.',
            tone: FlowTone.info),
      if (available)
        Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
          if (closed)
            OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _apply(ConversationAction.reopen,
                        conversation.workflowRevision),
                child: Text(ConversationAction.reopen.label)),
          if (!closed && !mine)
            claimPrimary
                ? FilledButton(
                    onPressed: disabled
                        ? null
                        : () => _apply(ConversationAction.claim,
                            conversation.workflowRevision),
                    child: Text(ConversationAction.claim.label))
                : OutlinedButton(
                    onPressed: null,
                    child: Text(ConversationAction.claim.label)),
          if (!closed && conversation.assignedTo != null)
            OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _apply(ConversationAction.release,
                        conversation.workflowRevision),
                child: Text(ConversationAction.release.label)),
          if (!closed)
            OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _apply(ConversationAction.resolve,
                        conversation.workflowRevision),
                child: Text(ConversationAction.resolve.label)),
        ]),
      if (admin && !closed) ...[
        const SizedBox(height: FlowSpace.lg),
        Eyebrow('Başka bir temsilciye ata', color: c.muted),
        const SizedBox(height: FlowSpace.sm),
        team.when(
          skipLoadingOnRefresh: false,
          data: (_) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Temsilci'),
                items: members
                    .map((member) => DropdownMenuItem(
                        value: member.id,
                        child:
                            Text(member.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: disabled
                    ? null
                    : (value) => setState(() => _assigneeId = value)),
            const SizedBox(height: FlowSpace.sm),
            OutlinedButton(
                onPressed: disabled || selected == null
                    ? null
                    : () => _apply(ConversationAction.assign,
                        conversation.workflowRevision,
                        assigneeId: selected),
                child: Text(ConversationAction.assign.label)),
            if (members.isEmpty) ...[
              const SizedBox(height: FlowSpace.sm),
              Text('Atanabilecek temsilci bulunamadı.',
                  style: theme.textTheme.bodySmall),
            ],
          ]),
          error: (_, __) => const InboxNotice(
              'Ekip yüklenemedi. Yenile düğmesiyle tekrar deneyin.'),
          loading: () => const SizedBox(
              height: 64, child: Center(child: CircularProgressIndicator())),
        ),
      ],
      const SizedBox(height: FlowSpace.sm),
      Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: disabled ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Yenile'))),
    ]);
  }

  void _refresh() {
    ref.invalidate(conversationDetailProvider(widget.scope));
    ref.invalidate(conversationTeamProvider(widget.scope));
  }

  Future<void> _apply(ConversationAction action, int revision,
      {String? assigneeId}) async {
    if (_invalidated || !_currentScope) return;
    final success = await ref
        .read(conversationWorkflowProvider(widget.scope).notifier)
        .apply(action, revision, assigneeId: assigneeId);
    if (!mounted || _invalidated || !_currentScope) return;
    _refresh();
    ref.invalidate(conversationsProvider);
    ref.invalidate(handoffRequestsProvider);
    ref.invalidate(messagesProvider(widget.scope.conversationId));
    if (success) {
      ref.read(handoffPageProvider.notifier).state = 0;
      showAppSnack(context, 'Konuşma güncellendi.');
      setState(() => _allowClose = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  Future<void> _close() async {
    final state = ref.read(conversationWorkflowProvider(widget.scope));
    if (state.busy || _closing) return;
    _closing = true;
    if (state.pending != null) {
      final leave = await confirmAction(
        context,
        title: 'Sonuç kontrolünden çıkılsın mı?',
        message:
            'İşlem sunucuda tamamlanmış olabilir. Çıkarsanız konuşmanın güncel durumunu gelen kutusundan kontrol edin.',
        confirmLabel: 'Çık',
        cancelLabel: 'Kontrole devam et',
      );
      if (!mounted) return;
      if (!leave) {
        _closing = false;
        return;
      }
    }
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }
}
