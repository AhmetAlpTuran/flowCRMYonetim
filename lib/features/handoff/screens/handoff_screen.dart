import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inbox/providers/inbox_providers.dart';
import '../../inbox/screens/chat_screen.dart';
import '../../inbox/widgets/conversation_workflow_sheet.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/handoff_request.dart';
import '../providers/handoff_providers.dart';

class HandoffScreen extends ConsumerStatefulWidget {
  const HandoffScreen({super.key});

  @override
  ConsumerState<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends ConsumerState<HandoffScreen> {
  String? _opening;
  ({String tenantId, String userId, String text})? _openError;

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(selectedTenantProvider)?.id;
    final userId = ref.watch(authControllerProvider).valueOrNull?.userId;
    final canOpen = ref
            .watch(currentMembershipProvider)
            .valueOrNull
            ?.hasPermission('inbox') ??
        false;
    final requests = ref.watch(handoffRequestsProvider);
    final page = ref.watch(handoffPageProvider);
    final status = ref.watch(handoffStatusProvider);
    final hasNext = (requests.valueOrNull?.length ?? 0) > handoffPageSize;
    if (tenantId == null || userId == null) {
      return const Center(
          child: Text('Yönlendirmeleri görmek için bir işletme seçin.'));
    }
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Yönlendirmeler', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final filter in <String?, String>{
          'open': 'Bekleyen',
          'in_progress': 'İşlemde',
          'done': 'Tamamlanan',
          null: 'Tümü'
        }.entries)
          ChoiceChip(
              label: Text(filter.value),
              selected: status == filter.key,
              onSelected: (_) {
                ref.read(handoffPageProvider.notifier).state = 0;
                ref.read(handoffStatusProvider.notifier).state = filter.key;
              }),
        TextButton.icon(
            onPressed: requests.isLoading
                ? null
                : () {
                    ref.read(handoffPageProvider.notifier).state = 0;
                    ref.invalidate(handoffRequestsProvider);
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Yenile')),
      ]),
      if (!canOpen)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                'Konuşmaları açmak ve yönetmek için gelen kutusu yetkisi gerekir.')),
      if (_openError?.tenantId == tenantId && _openError?.userId == userId)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(
                liveRegion: true,
                child: Text(_openError!.text,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)))),
      const SizedBox(height: 12),
      requests.when(
        skipLoadingOnRefresh: false,
        data: (items) => items.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(page == 0
                    ? 'Bu filtreye uyan yönlendirme bulunamadı.'
                    : 'Bu sayfada kayıt kalmadı. Önceki sayfaya dönün.'))
            : Column(
                children: items
                    .take(20)
                    .map((request) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                              child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(request.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 6),
                                  Text(
                                      '${_statusLabel(request.status)} • ${_formatDate(request.createdAt, context)}'),
                                  if (request.note?.isNotEmpty ?? false) ...[
                                    const SizedBox(height: 8),
                                    Text(request.note!),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    OutlinedButton.icon(
                                        onPressed: !canOpen || _opening != null
                                            ? null
                                            : () => _openConversation(
                                                request, tenantId, userId),
                                        icon: _opening == request.id
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(
                                                Icons.chat_bubble_outline),
                                        label: const Text('Konuşmayı aç')),
                                    TextButton.icon(
                                        onPressed: !canOpen
                                            ? null
                                            : () => showConversationWorkflow(
                                                    context, (
                                                  tenantId: tenantId,
                                                  conversationId:
                                                      request.conversationId,
                                                  userId: userId
                                                )),
                                        icon: const Icon(
                                            Icons.manage_accounts_outlined),
                                        label: const Text('Konuşmayı yönet')),
                                  ]),
                                ]),
                          )),
                        ))
                    .toList()),
        error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              const Text(
                  'Yönlendirmeler yüklenemedi. Yetkinizi ve bağlantınızı kontrol edin.'),
              TextButton(
                  onPressed: () => ref.invalidate(handoffRequestsProvider),
                  child: const Text('Tekrar dene')),
            ])),
        loading: () => const SizedBox(
            height: 200, child: Center(child: CircularProgressIndicator())),
      ),
      Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
                onPressed: requests.isLoading || page == 0
                    ? null
                    : () =>
                        ref.read(handoffPageProvider.notifier).state = page - 1,
                child: const Text('Önceki')),
            Text('Sayfa ${page + 1} • En fazla $handoffPageSize kayıt'),
            TextButton(
                onPressed: requests.isLoading || requests.hasError || !hasNext
                    ? null
                    : () =>
                        ref.read(handoffPageProvider.notifier).state = page + 1,
                child: const Text('Sonraki')),
          ]),
    ]);
  }

  Future<void> _openConversation(
      HandoffRequest request, String tenantId, String userId) async {
    if (_opening != null) return;
    setState(() {
      _opening = request.id;
      _openError = null;
    });
    try {
      final conversation = await ref
          .read(inboxRepositoryProvider)
          .fetchConversation(
              tenantId: tenantId, conversationId: request.conversationId);
      if (!mounted ||
          ref.read(selectedTenantProvider)?.id != tenantId ||
          ref.read(authControllerProvider).valueOrNull?.userId != userId) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversation: conversation)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _openError = (
            tenantId: tenantId,
            userId: userId,
            text:
                'Konuşma açılamadı. Erişiminizi kontrol edip Konuşmayı aç düğmesiyle tekrar deneyin.'
          ));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  String _statusLabel(String value) => switch (value) {
        'open' => 'Bekliyor',
        'in_progress' => 'İşlemde',
        'done' => 'Tamamlandı',
        _ => 'Durum bilinmiyor',
      };

  String _formatDate(DateTime value, BuildContext context) {
    final local = value.toLocal();
    return '${MaterialLocalizations.of(context).formatMediumDate(local)} ${TimeOfDay.fromDateTime(local).format(context)}';
  }
}
