import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../models/dashboard_metrics.dart';
import '../providers/dashboard_providers.dart';

/// One member's numbers from `dashboard_agent_metrics`.
class AgentMetric {
  const AgentMetric({
    required this.name,
    required this.role,
    required this.replies,
    required this.firstResponses,
    required this.resolved,
    required this.openAssigned,
    this.medianFirstResponse,
  });

  factory AgentMetric.fromJson(Map<String, dynamic> json) => AgentMetric(
        name: json['name'] as String? ?? 'Kullanıcı',
        role: json['role'] as String? ?? 'user',
        replies: (json['replies'] as num?)?.toInt() ?? 0,
        firstResponses: (json['first_responses'] as num?)?.toInt() ?? 0,
        resolved: (json['resolved'] as num?)?.toInt() ?? 0,
        openAssigned: (json['open_assigned'] as num?)?.toInt() ?? 0,
        medianFirstResponse: json['median_first_response_seconds'] is num
            ? Duration(milliseconds: ((json['median_first_response_seconds'] as num) * 1000).round())
            : null,
      );

  final String name;
  final String role;
  final int replies;
  final int firstResponses;
  final int resolved;
  final int openAssigned;
  final Duration? medianFirstResponse;
}

typedef AgentMetricsLoader = Future<List<AgentMetric>> Function(String tenantId, int days);

/// Loads per-agent metrics; overridden in widget tests.
final agentMetricsLoaderProvider = Provider<AgentMetricsLoader>((ref) => (tenantId, days) async {
      final data = await Supabase.instance.client.rpc('dashboard_agent_metrics', params: {
        'p_tenant_id': tenantId,
        'p_days': days,
        'p_timezone': 'Europe/Istanbul',
      }).timeout(const Duration(seconds: 20));
      final agents = (data as Map)['agents'] as List? ?? const [];
      return [for (final a in agents) AgentMetric.fromJson(Map<String, dynamic>.from(a as Map))];
    });

/// Null for members who are not administrators (the section is hidden).
final agentMetricsProvider = FutureProvider<List<AgentMetric>?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  bool admin;
  try {
    admin = (await ref.watch(currentMembershipProvider.future))?.isAdmin == true;
  } catch (_) {
    admin = false;
  }
  if (tenant == null || !admin) return null;
  return ref.watch(agentMetricsLoaderProvider)(tenant.id, ref.watch(dashboardPeriodProvider));
});

/// "Ekip performansı" on the dashboard (administrators).
class AgentPerformanceSection extends ConsumerWidget {
  const AgentPerformanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentMetricsProvider);
    return agents.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Ekip performansı yüklenemedi.'),
          trailing: TextButton(
            onPressed: () => ref.invalidate(agentMetricsProvider),
            child: const Text('Tekrar dene'),
          ),
        ),
      ),
      data: (list) {
        if (list == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          Text('Ekip performansı', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Card(child: ListTile(title: Text('Henüz ekip üyesi yok.')))
          else
            Card(
              child: Column(children: [
                for (final (index, agent) in list.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(agent.name.isEmpty ? '?' : agent.name.characters.first.toUpperCase()),
                    ),
                    title: Text(agent.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${agent.replies} yanıt · ilk yanıt ${formatDuration(agent.medianFirstResponse)}'
                      ' · ${agent.resolved} çözüldü · ${agent.openAssigned} açık konuşma',
                    ),
                    isThreeLine: true,
                  ),
                ],
              ]),
            ),
        ]);
      },
    );
  }
}
