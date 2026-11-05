import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../inbox/models/conversation.dart';
import '../../inbox/providers/inbox_providers.dart';
import '../../shell/shell_providers.dart';
import '../models/dashboard_metrics.dart';

/// A conversation that still waits for the team: unread customer messages, or a
/// request for a human agent.
bool needsAttention(Conversation item) =>
    item.status != ConversationStatus.closed &&
    (item.unreadCount > 0 || item.status == ConversationStatus.handoff);

/// Open conversations with unread customer messages (the shell's live count).
bool isWaitingForReply(Conversation item) => item.status != ConversationStatus.closed && item.unreadCount > 0;

/// Waiting conversations, longest waiting first.
List<Conversation> attentionQueue(List<Conversation> conversations) =>
    conversations.where(needsAttention).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

/// The live hero on the dashboard: how many customers wait right now and one way in.
class LiveQueueHero extends ConsumerWidget {
  const LiveQueueHero({super.key, required this.conversations, this.metrics, this.handoffAllowed = false});

  final AsyncValue<List<Conversation>> conversations;

  /// Server counts for the side tiles; omitted until they load.
  final DashboardMetrics? metrics;
  final bool handoffAllowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FlowColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.panelAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGrid(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final ringSize = wide ? 460.0 : 300.0;
          final content = _content(context, ref, wide: wide);
          final counters = metrics == null ? null : _HeroCounters(metrics: metrics!);
          return Stack(children: [
            Positioned(
              right: wide ? -120 : -110,
              top: wide ? -150 : -110,
              child: SignalRings(size: ringSize, rings: 3),
            ),
            Padding(
              padding: EdgeInsets.all(wide ? 30 : 18),
              child: wide && counters != null
                  ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: content),
                      const SizedBox(width: 28),
                      SizedBox(width: 360, child: counters),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      content,
                      if (counters != null) ...[const SizedBox(height: 18), counters],
                    ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, {required bool wide}) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final headlineStyle = (wide ? theme.textTheme.displaySmall : theme.textTheme.headlineMedium);
    final bodyStyle = (wide ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)?.copyWith(color: c.muted);

    void openInbox() => openShellDestination(ref, ShellDestinationId.inbox);
    void openHandoff() => openShellDestination(ref, ShellDestinationId.handoff);

    Widget fill(Widget button) => wide ? button : SizedBox(width: double.infinity, child: button);

    String headline;
    Widget? body;
    final actions = <Widget>[];
    final value = conversations.valueOrNull;
    if (value != null) {
      final waiting = value.where(isWaitingForReply).length;
      final handoffs = value.where((item) => item.status == ConversationStatus.handoff).length;
      final oldest = attentionQueue(value).firstOrNull;
      final handoffButton = handoffAllowed && handoffs > 0
          ? fill(OutlinedButton(onPressed: openHandoff, child: const Text('Temsilci bekleyenleri aç')))
          : null;
      if (waiting > 0) {
        headline = '$waiting müşteri yanıt bekliyor.';
        actions.add(fill(FilledButton(
          onPressed: openInbox,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('Sırayla yanıtla')),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 18),
          ]),
        )));
        if (handoffButton != null) actions.add(handoffButton);
      } else if (handoffs > 0) {
        headline = '$handoffs sohbet temsilci bekliyor.';
        actions.add(handoffButton ?? fill(OutlinedButton(onPressed: openInbox, child: const Text('Sohbetlere git'))));
      } else {
        headline = 'Bekleyen sohbet yok.';
        actions.add(fill(OutlinedButton(onPressed: openInbox, child: const Text('Sohbetlere git'))));
      }
      body = oldest == null
          ? Text('Yeni bir mesaj geldiğinde burada görünür.', style: bodyStyle)
          : Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'En uzun bekleyen '),
                TextSpan(
                  text: oldest.title,
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: ' · '),
                TextSpan(
                  text: upperTr(formatAgo(oldest.updatedAt)),
                  style: FlowText.mono(context, size: (bodyStyle?.fontSize ?? 15) - 2, color: c.warning),
                ),
              ]),
              style: bodyStyle,
            );
    } else if (conversations.hasError) {
      headline = 'Sohbetler yüklenemedi.';
      body = Text('Bağlantınızı kontrol edip tekrar deneyin.', style: bodyStyle);
      actions.add(fill(OutlinedButton.icon(
        onPressed: () => ref.invalidate(conversationsProvider),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Tekrar dene'),
      )));
    } else {
      headline = 'Kuyruk yükleniyor…';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const LiveLine('Canlı · şu an'),
      SizedBox(height: wide ? 14 : 10),
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(
          headline,
          style: value != null ? headlineStyle : headlineStyle?.copyWith(color: c.muted),
        ),
      ),
      if (body != null) ...[const SizedBox(height: FlowSpace.sm), body],
      if (actions.isNotEmpty) ...[
        SizedBox(height: wide ? 22 : 14),
        Wrap(spacing: 10, runSpacing: 10, children: actions),
      ],
    ]);
  }
}

/// Three server counters beside the hero text: open, waiting for an agent, unassigned.
class _HeroCounters extends StatelessWidget {
  const _HeroCounters({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final tiles = [
      ('Açık', m.openConversations + m.pendingConversations, FlowTone.accent),
      ('Temsilci', m.handoffConversations, FlowTone.warning),
      ('Atanmamış', m.unassignedWaiting, FlowTone.info),
    ];
    return Row(children: [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(width: FlowSpace.sm),
        Expanded(child: _CounterTile(label: tiles[i].$1, value: tiles[i].$2, tone: tiles[i].$3)),
      ],
    ]);
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final FlowTone tone;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.md + 2),
        decoration: BoxDecoration(
          color: c.canvas,
          borderRadius: FlowRadius.cardAll,
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(upperTr(label), style: FlowText.caps(context, size: 10, color: c.toneText(tone))),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatCount(value), style: FlowText.number(context, size: 38)),
          ),
        ]),
      ),
    );
  }
}

/// "Dikkat bekleyenler": the oldest waiting conversations, each one tap from the inbox.
class AttentionList extends ConsumerWidget {
  const AttentionList({super.key, required this.conversations, this.limit = 5});

  final List<Conversation> conversations;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FlowColors.of(context);
    final queue = attentionQueue(conversations);
    void openInbox() => openShellDestination(ref, ShellDestinationId.inbox);
    return SectionCard(
      title: 'Dikkat bekleyenler',
      flush: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(formatCount(queue.length), style: FlowText.mono(context, size: 12)),
        const SizedBox(width: FlowSpace.sm),
        TextButton(onPressed: openInbox, child: const Text('Tümü')),
      ]),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 460;
        final shown = queue.take(limit).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (index, item) in shown.indexed) ...[
            if (index > 0) Divider(height: 1, color: c.border),
            _AttentionRow(conversation: item, wide: wide, onOpen: openInbox),
          ],
        ]);
      }),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.conversation, required this.wide, required this.onOpen});

  final Conversation conversation;
  final bool wide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final handoff = conversation.status == ConversationStatus.handoff;
    final badge = handoff
        ? const StatusBadge('Temsilci bekliyor', tone: FlowTone.warning)
        : const StatusBadge('Yanıt bekliyor', tone: FlowTone.info);
    final name = Text(
      conversation.title,
      style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final elapsed = formatAgo(conversation.updatedAt);
    return Semantics(
      button: true,
      label: '${conversation.title}, ${handoff ? 'temsilci bekliyor' : 'yanıt bekliyor'}, $elapsed',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 20 : FlowSpace.lg, vertical: wide ? FlowSpace.lg : FlowSpace.md),
          child: Row(children: [
            InitialsAvatar(conversation.title.isEmpty ? '?' : conversation.title, size: wide ? 40 : 38),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (wide)
                  Wrap(
                    spacing: FlowSpace.sm,
                    runSpacing: FlowSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [name, badge],
                  )
                else ...[
                  name,
                  const SizedBox(height: FlowSpace.xs),
                  badge,
                ],
                if (wide && conversation.lastMessage.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    conversation.lastMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ]),
            ),
            const SizedBox(width: FlowSpace.md),
            Text(upperTr(elapsed), style: FlowText.mono(context, size: 12, color: handoff ? c.warning : c.muted)),
            if (wide) ...[
              const SizedBox(width: 14),
              OutlinedButton(onPressed: onOpen, child: const Text('Yanıtla')),
            ],
          ]),
        ),
      ),
    );
  }
}
