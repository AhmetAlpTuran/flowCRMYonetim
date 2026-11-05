import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard_metrics.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/agent_performance.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final days = ref.watch(dashboardPeriodProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(agentMetricsProvider)
          ..invalidate(dashboardMetricsProvider);
        await ref.read(dashboardMetricsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Panel', style: Theme.of(context).textTheme.titleLarge),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Bugün')),
                  ButtonSegment(value: 7, label: Text('7 gün')),
                  ButtonSegment(value: 30, label: Text('30 gün')),
                ],
                selected: {days},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    ref.read(dashboardPeriodProvider.notifier).state = value.first,
              ),
            ],
          ),
          const SizedBox(height: 16),
          metrics.when(
            data: (data) => data == null
                ? const SizedBox.shrink()
                : _MetricsView(metrics: data),
            error: (_, __) => Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Panel yüklenemedi.'),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(dashboardMetricsProvider),
                  child: const Text('Tekrar dene'),
                ),
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          const AgentPerformanceSection(),
        ],
      ),
    );
  }
}

class _MetricsView extends StatelessWidget {
  const _MetricsView({required this.metrics});
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Şu an'),
        _CardGrid(children: [
          _StatCard(
            icon: Icons.mark_email_unread_outlined,
            title: 'Açık konuşma',
            value: '${m.openConversations + m.pendingConversations}',
            color: scheme.primaryContainer,
          ),
          _StatCard(
            icon: Icons.headset_mic_outlined,
            title: 'Temsilci bekleyen',
            value: '${m.handoffConversations}',
            color: scheme.tertiaryContainer,
          ),
          _StatCard(
            icon: Icons.person_off_outlined,
            title: 'Atanmamış bekleyen',
            value: '${m.unassignedWaiting}',
            color: scheme.secondaryContainer,
          ),
        ]),
        const SizedBox(height: 16),
        _SectionTitle(m.periodDays == 1 ? 'Bugün' : 'Son ${m.periodDays} gün'),
        _CardGrid(children: [
          _StatCard(
            icon: Icons.forum_outlined,
            title: 'Gelen mesaj',
            value: '${m.inboundMessages}',
            subtitle: '${m.startedConversations} yeni konuşma',
            color: scheme.primaryContainer,
          ),
          _StatCard(
            icon: Icons.smart_toy_outlined,
            title: 'Bot yanıt oranı',
            value: formatPercent(m.botShare),
            subtitle: '${m.botReplies} bot · ${m.humanReplies} temsilci',
            color: scheme.secondaryContainer,
          ),
          _StatCard(
            icon: Icons.timer_outlined,
            title: 'İlk yanıt süresi (medyan)',
            value: formatDuration(m.medianFirstResponse),
            subtitle: 'Temsilci: ${formatDuration(m.medianFirstHumanResponse)}',
            color: scheme.tertiaryContainer,
          ),
          _StatCard(
            icon: Icons.task_alt_outlined,
            title: 'Çözülen talep',
            value: '${m.supportResolved} / ${m.supportOpened}',
            subtitle: 'Çözüm süresi: ${formatDuration(m.medianResolution)}',
            color: scheme.primaryContainer,
          ),
          _StatCard(
            icon: Icons.support_agent_outlined,
            title: 'Temsilciye yönlendirme',
            value: '${m.handoffs}',
            color: scheme.surfaceContainerHighest,
          ),
          if (m.failedReplies > 0)
            _StatCard(
              icon: Icons.error_outline,
              title: 'Gönderilemeyen yanıt',
              value: '${m.failedReplies}',
              color: scheme.errorContainer,
            ),
        ]),
        if (m.campaignAccepted > 0) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Kampanyalar'),
          _CardGrid(children: [
            _StatCard(
              icon: Icons.campaign_outlined,
              title: 'Gönderilen',
              value: '${m.campaignAccepted}',
              subtitle: m.campaignFailed > 0 ? '${m.campaignFailed} başarısız' : null,
              color: scheme.primaryContainer,
            ),
            _StatCard(
              icon: Icons.done_all,
              title: 'Teslim edilen',
              value: formatPercent(m.deliveryRate),
              color: scheme.secondaryContainer,
            ),
            _StatCard(
              icon: Icons.visibility_outlined,
              title: 'Okunan',
              value: formatPercent(m.readRate),
              color: scheme.tertiaryContainer,
            ),
          ]),
        ],
        if (m.daily.length > 1) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Günlük mesaj trafiği'),
          ActivityChart(days: m.daily),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        // Two columns on phones, more on wider screens.
        final columns = (constraints.maxWidth / 220).floor().clamp(2, 4);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      });
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 20),
            ),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.labelMedium, maxLines: 2),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.headlineSmall),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

/// Paired daily bars: customer messages and replies.
class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key, required this.days});
  final List<DailyActivity> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = days.fold<int>(1, (max, d) {
      final value = d.inbound > d.replies ? d.inbound : d.replies;
      return value > max ? value : max;
    });
    final labelEvery = (days.length / 7).ceil();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Tooltip(
                      message: '${day.day.day}.${day.day.month}: '
                          '${day.inbound} gelen, ${day.replies} yanıt',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Bar(fraction: day.inbound / peak, color: scheme.primary),
                          _Bar(fraction: day.replies / peak, color: scheme.tertiary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Text(
                  i % labelEvery == 0 ? '${days[i].day.day}.${days[i].day.month}' : '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 16, children: [
            _Legend(color: scheme.primary, label: 'Gelen mesaj'),
            _Legend(color: scheme.tertiary, label: 'Yanıt'),
          ]),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: FractionallySizedBox(
          heightFactor: fraction <= 0 ? 0.01 : fraction,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
