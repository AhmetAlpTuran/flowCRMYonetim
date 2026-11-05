import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../inbox/providers/inbox_providers.dart';
import '../../inbox/screens/chat_screen.dart';
import '../../inbox/widgets/conversation_badge.dart';
import '../../inbox/widgets/conversation_workflow_sheet.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/handoff_request.dart';
import '../providers/handoff_providers.dart';

/// "Temsilci bekleyen": handoff requests in pages of [handoffPageSize], filtered by
/// status, each opening its chat or the shared workflow sheet.
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
      return const AppPage(children: [
        EmptyState(
          icon: Icons.storefront_outlined,
          title: 'İşletme seçin',
          message: 'Temsilci bekleyen sohbetleri görmek için bir işletme seçin.',
        ),
      ]);
    }
    final chips = FilterChipsRow<String?>(
      selected: status,
      onSelected: (value) {
        ref.read(handoffPageProvider.notifier).state = 0;
        ref.read(handoffStatusProvider.notifier).state = value;
      },
      options: const [
        FilterOption('open', 'Bekleyen'),
        FilterOption('in_progress', 'İşlemde'),
        FilterOption('done', 'Tamamlanan'),
        FilterOption(null, 'Tümü'),
      ],
    );
    final VoidCallback? refresh = requests.isLoading
        ? null
        : () {
            ref.read(handoffPageProvider.notifier).state = 0;
            ref.invalidate(handoffRequestsProvider);
          };
    return AppPage(
      toolbar: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: chips),
                const SizedBox(width: FlowSpace.sm),
                IconButton.outlined(
                  tooltip: 'Yenile',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ])
            : PageToolbar(
                leading: chips,
                actions: [
                  OutlinedButton.icon(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Yenile')),
                ],
              ),
      ),
      children: [
        if (!canOpen)
          const InboxNotice(
            'Konuşmaları açmak ve yönetmek için gelen kutusu yetkisi gerekir.',
            tone: FlowTone.info,
          ),
        if (_openError?.tenantId == tenantId && _openError?.userId == userId)
          InboxNotice(_openError!.text),
        requests.when(
          skipLoadingOnRefresh: false,
          data: (items) => items.isEmpty
              ? EmptyState(
                  compact: true,
                  icon: Icons.support_agent_outlined,
                  title: page == 0 ? 'Bekleyen aktarım yok' : 'Bu sayfada kayıt kalmadı',
                  message: page == 0
                      ? 'Bu filtreye uyan aktarım bulunamadı.'
                      : 'Önceki sayfaya dönün.',
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (index, request) in items.take(handoffPageSize).indexed) ...[
                    if (index > 0) const SizedBox(height: FlowSpace.md),
                    _HandoffCard(
                      key: ValueKey(request.id),
                      request: request,
                      opening: _opening == request.id,
                      onOpen: !canOpen || _opening != null
                          ? null
                          : () => _openConversation(request, tenantId, userId),
                      onManage: !canOpen
                          ? null
                          : () => showConversationWorkflow(context, (
                                tenantId: tenantId,
                                conversationId: request.conversationId,
                                userId: userId
                              )),
                    ),
                  ],
                ]),
          error: (_, __) => ErrorState(
            title: 'Aktarımlar yüklenemedi',
            message: 'Yetkinizi ve bağlantınızı kontrol edip tekrar deneyin.',
            onRetry: () => ref.invalidate(handoffRequestsProvider),
          ),
          loading: () => const LoadingList(rows: 4),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final previous = TextButton.icon(
              onPressed: requests.isLoading || page == 0
                  ? null
                  : () => ref.read(handoffPageProvider.notifier).state = page - 1,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Önceki'));
          final next = TextButton.icon(
              onPressed: requests.isLoading || requests.hasError || !hasNext
                  ? null
                  : () => ref.read(handoffPageProvider.notifier).state = page + 1,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Sonraki'));
          final label = Text(upperTr('Sayfa ${page + 1} · en fazla $handoffPageSize kayıt'),
              textAlign: TextAlign.center, style: FlowText.caps(context, size: 10));
          if (constraints.maxWidth >= 420) {
            return Row(children: [previous, Expanded(child: label), next]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label,
            const SizedBox(height: FlowSpace.xs),
            Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: FlowSpace.xs, children: [previous, next]),
          ]);
        }),
      ],
    );
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
}

({String label, FlowTone tone}) _statusOf(String value) => switch (value) {
      'open' => (label: 'Bekliyor', tone: FlowTone.warning),
      'in_progress' => (label: 'İşlemde', tone: FlowTone.info),
      'done' => (label: 'Tamamlandı', tone: FlowTone.accent),
      _ => (label: 'Durum bilinmiyor', tone: FlowTone.neutral),
    };

/// "6 dk önce", "şimdi", or a date for older requests.
String _elapsed(DateTime createdAt) {
  final ago = formatAgo(createdAt);
  final age = DateTime.now().difference(createdAt);
  if (age.inMinutes < 1 || age.inDays >= 7) return ago;
  return '$ago önce';
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({
    super.key,
    required this.request,
    required this.opening,
    required this.onOpen,
    required this.onManage,
  });

  final HandoffRequest request;
  final bool opening;
  final VoidCallback? onOpen;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final status = _statusOf(request.status);
    final note = request.note?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InitialsAvatar(request.title, size: 40),
          const SizedBox(width: FlowSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Wrap(
                spacing: FlowSpace.sm,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(status.label, tone: status.tone),
                  Tooltip(
                    message: formatDateTime(request.createdAt),
                    child: Text(upperTr(_elapsed(request.createdAt)),
                        style: FlowText.caps(context, size: 10, color: c.faint)),
                  ),
                ],
              ),
            ]),
          ),
        ]),
        if (note.isNotEmpty) ...[
          const SizedBox(height: FlowSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: 10),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: FlowRadius.controlAll,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NOT', style: FlowText.caps(context, size: 10)),
              const SizedBox(height: 4),
              Text(note, style: theme.textTheme.bodyMedium),
            ]),
          ),
        ],
        const SizedBox(height: FlowSpace.md),
        Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
          OutlinedButton.icon(
              onPressed: onOpen,
              icon: opening
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Konuşmayı aç')),
          TextButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.manage_accounts_outlined, size: 18),
              label: const Text('Konuşmayı yönet')),
        ]),
      ]),
    );
  }
}
