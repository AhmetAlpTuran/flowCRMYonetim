import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../handoff/providers/handoff_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/conversation.dart';
import '../models/conversation_action.dart';
import '../providers/conversation_workflow_provider.dart';
import '../providers/inbox_providers.dart';

Future<bool?> showConversationWorkflow(
    BuildContext context, ConversationScope scope) {
  return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ConversationWorkflowSheet(scope: scope));
}

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
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Konuşmayı yönet',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (!canAct)
                  const Text(
                      'Oturum, işletme veya yetkiniz değişti. Bu pencereyi kapatıp gelen kutusuna dönün.')
                else
                  ref.watch(conversationDetailProvider(widget.scope)).when(
                        skipLoadingOnRefresh: false,
                        data: (conversation) =>
                            _actions(conversation, membership!.isAdmin, state),
                        error: (_, __) => Column(children: [
                          const Text(
                              'Konuşma yüklenemedi. Erişiminizi kontrol edip tekrar deneyin.'),
                          TextButton(
                              onPressed: state.busy ? null : _refresh,
                              child: const Text('Yenile')),
                        ]),
                        loading: () => const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator())),
                      ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                      liveRegion: true,
                      child: Text(state.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                ],
                if (canAct && state.pending != null) ...[
                  const SizedBox(height: 12),
                  Text('Bekleyen işlem • ${state.pending!.action.label}'),
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
                          : const Icon(Icons.refresh),
                      label: const Text('Aynı isteği kontrol et')),
                ],
                const SizedBox(height: 16),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: state.busy ? null : _close,
                        child: const Text('Kapat'))),
              ]),
        )),
      )),
    );
  }

  Widget _actions(
      Conversation conversation, bool admin, ConversationWorkflowState state) {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(conversation.title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('${conversation.status.label} • $owner'),
      const SizedBox(height: 12),
      const Text(
          'Üstlenilen konuşmalar insan kontrolünde kalır. Çözüm, mevcut destek kaydını kapatır. Yeni bir müşteri mesajı yeni kayıt açabilir.'),
      const SizedBox(height: 16),
      if (!available)
        const Text(
            'Konuşma başka bir temsilcide. Atamayı değiştirmek için yöneticinize başvurun.'),
      if (available)
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (closed)
            OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => _apply(ConversationAction.reopen,
                        conversation.workflowRevision),
                child: Text(ConversationAction.reopen.label)),
          if (!closed && !mine)
            FilledButton(
                onPressed: disabled
                    ? null
                    : () => _apply(ConversationAction.claim,
                        conversation.workflowRevision),
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
        const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: disabled || selected == null
                    ? null
                    : () => _apply(ConversationAction.assign,
                        conversation.workflowRevision,
                        assigneeId: selected),
                child: Text(ConversationAction.assign.label)),
            if (members.isEmpty)
              const Text('Atanabilecek temsilci bulunamadı.'),
          ]),
          error: (_, __) =>
              const Text('Ekip yüklenemedi. Yenile düğmesiyle tekrar deneyin.'),
          loading: () => const SizedBox(
              height: 64, child: Center(child: CircularProgressIndicator())),
        ),
      ],
      Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: disabled ? null : _refresh,
              icon: const Icon(Icons.refresh),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Konuşma güncellendi.')));
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
      final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Sonuç kontrolünden çıkılsın mı?'),
                  content: const Text(
                      'İşlem sunucuda tamamlanmış olabilir. Çıkarsanız konuşmanın güncel durumunu gelen kutusundan kontrol edin.'),
                  actions: [
                    TextButton(
                        autofocus: true,
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Kontrole devam et')),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Çık'))
                  ]));
      if (!mounted) return;
      if (leave != true) {
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
