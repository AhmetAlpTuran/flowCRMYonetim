import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dashboard_providers.dart';
import '../widgets/chart_placeholder.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);

    return stats.when(
      data: (data) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                title: 'Bugun gorusmeler',
                value: data.totalToday.toString(),
                color: Theme.of(context).colorScheme.primaryContainer,
                icon: Icons.forum_outlined,
              ),
              _StatCard(
                title: 'Acik',
                value: data.openCount.toString(),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                icon: Icons.mark_email_unread_outlined,
              ),
              _StatCard(
                title: 'Beklemede',
                value: data.pendingCount.toString(),
                color: Theme.of(context).colorScheme.secondaryContainer,
                icon: Icons.schedule_outlined,
              ),
              _StatCard(
                title: 'Müşteri temsilcisine yönlendir',
                value: data.handoffCount.toString(),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                icon: Icons.headset_mic_outlined,
              ),
              _StatCard(
                title: 'Tahmini müşteri memnuniyeti',
                value: '%${data.estimatedSatisfactionPercent}',
                color: Theme.of(context).colorScheme.primaryContainer,
                icon: Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Aktivite',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const ChartPlaceholder(),
          const SizedBox(height: 24),
          Text(
            'Hizli islemler',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickAction(
                icon: Icons.playlist_add_check,
                label: 'Yeni talepleri incele',
              ),
              _QuickAction(
                icon: Icons.person_add_alt_1,
                label: 'Temsilciye yönlendir',
              ),
              _QuickAction(
                icon: Icons.campaign,
                label: 'Duyuru paylas',
              ),
              _QuickAction(
                icon: Icons.auto_awesome,
                label: 'Bot tonunu ayarla',
              ),
            ],
          ),
        ],
      ),
      error: (error, _) => Center(
        child: Text('Panel yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {},
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}
